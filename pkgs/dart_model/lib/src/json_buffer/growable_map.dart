// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'json_buffer_builder.dart';

/// Methods for writing and reading "growable maps".
///
/// A "growable map" is a `Map<String, Object?>` in a byte buffer that is
/// implemented as a linked list of entries, so it can accept new entries.
extension GrowableMaps on JsonBufferBuilder {
  // Layout:
  //
  // Empty map is [null pointer].
  //
  // Map with one entry is [pointer to first node], and that first node is
  // [null pointer, entry].
  //
  // Then each additional entry adds a [pointer, entry] and sets the null
  // pointer in the last entry to the new entry.
  //
  // Each entry is: [key (pointer to string), value type, value].
  //
  // Values are stored with `_writeAny`.
  static const _keySize = _pointerSize;
  static const _valueSize = _typeSize + _pointerSize;
  static const _entrySize = _pointerSize + _keySize + _valueSize;

  /// Creates a "growable map".
  ///
  /// It can have new values added to it, hence "growable".
  ///
  /// It is linked to the `JsonBufferBuilder` that creates it: it can be added
  /// to any collection in the same `JsonBufferBuilder` without copying.
  /// Adding to a collection in a different `JsonBufferBuilder` is an error.
  ///
  /// The caller is responsible for adding a reference to the returned value
  /// somewhere in the buffer. Otherwise, it won't be reachable from the
  /// root [map].
  Map<String, V> createGrowableMap<V>() {
    _explanations?.push('addGrowableMap');
    final pointer = _reserve(_pointerSize + _lengthSize);
    // Initially a "growable map" is just a null pointer and zero size, so
    // there is nothing to write.
    _explanations?.pop();
    return _readGrowableMap<V>(pointer);
  }

  /// Returns the [_Pointer] to [map].
  ///
  /// The [map] must have been created in this buffer using
  /// [createGrowableMap]. Otherwise, [UnsupportedError] is thrown.
  _Pointer _pointerToGrowableMap(_GrowableMap<Object?> map) {
    _checkGrowableMapOwnership(map);
    return map._pointer;
  }

  /// Throws if [map is backed by a different buffer to `this`.
  void _checkGrowableMapOwnership(_GrowableMap map) {
    if (map._buffer != this) {
      throw UnsupportedError('Maps created with `createGrowableMap` can only '
          'be added to the JsonBufferBuilder instance that created them.');
    }
  }

  /// Returns the [_GrowableMap] at [pointer].
  Map<String, V> _readGrowableMap<V>(_Pointer pointer) {
    return _GrowableMap<V>(this, pointer);
  }
}

class _GrowableMap<V> with MapMixin<String, V>, _EntryMapMixin<String, V> {
  final JsonBufferBuilder _buffer;
  final _Pointer _pointer;
  int _length;
  _Pointer? _lastPointer;

  _GrowableMap(this._buffer, this._pointer)
      : _length = _buffer._readLength(_pointer + _pointerSize);

  @override
  int get length => _length;

  @override
  V? operator [](Object? key) {
    // TODO(davidmorgan): these maps could be large, we probably need a more
    // efficient lookup than linear search.
    final iterator = entries.iterator as _GrowableMapEntryIterator<V>;
    while (iterator.moveNext()) {
      if (iterator.current.key == key) return iterator.current.value;
    }
    return null;
  }

  @override
  late final Iterable<String> keys = _IteratorFunctionIterable(
      () => _GrowableMapKeyIterator(_buffer, _pointer),
      length: length);

  @override
  late final Iterable<V> values = _IteratorFunctionIterable(
      () => _GrowableMapValueIterator<V>(_buffer, _pointer),
      length: length);

  @override
  late final Iterable<MapEntry<String, V>> entries = _IteratorFunctionIterable(
      () => _GrowableMapEntryIterator(_buffer, _pointer),
      length: length);

  /// Add [value] to the map with key [key].
  ///
  /// This implementation does not correctly handle repeated adds with the
  /// same [key]. Repeated adds will _not_ updated the associated value but
  /// _will_ cause an increase in [length] and duplicates in the [keys]
  /// iterable.
  @override
  void operator []=(String key, V value) {
    _buffer._explanations?.push('GrowableMap[]= $key $value');

    // If `_lastPointer` is not set yet, walk the map to find the end of it.
    if (_lastPointer == null) {
      final iterator = _GrowableMapEntryIterator<V>(_buffer, _pointer);
      _lastPointer = _pointer;
      while (iterator.moveNext()) {
        _lastPointer = iterator._pointer;
      }
    }

    // Reserve and write the new node.
    final pointer = _buffer._reserve(GrowableMaps._entrySize);
    final entryPointer = pointer + _pointerSize;
    _buffer._writePointer(entryPointer, _buffer._pointerToString(key));
    _buffer._writeAny(entryPointer + _pointerSize, value);

    // Point to the new node in the previous node.
    _buffer._writePointer(_lastPointer!, pointer);
    // Update `_lastPointer` to the new node.
    _lastPointer = pointer;

    // Update length.
    ++_length;
    _buffer._writeLength(_pointer + _pointerSize, length, allowOverwrite: true);
    _buffer._explanations?.pop();
  }

  @override
  V remove(Object? key) {
    throw UnsupportedError('JsonBufferBuilder growable maps are append only.');
  }

  @override
  void clear() {
    throw UnsupportedError('JsonBufferBuilder growable maps are append only.');
  }
}

/// `Iterator` that reads a "growable map" in a [JsonBufferBuilder].
abstract class _GrowableMapIterator<T> implements Iterator<T> {
  final JsonBufferBuilder _buffer;
  _Pointer _pointer;

  _GrowableMapIterator(this._buffer, this._pointer);

  @override
  T get current;

  String get _currentKey =>
      _buffer._readString(_buffer._readPointer(_pointer + _pointerSize));
  Object? get _currentValue =>
      _buffer._readAny(_pointer + _pointerSize + GrowableMaps._keySize);

  @override
  bool moveNext() {
    _pointer = _buffer._readPointer(_pointer);
    return _pointer != 0;
  }
}

class _GrowableMapKeyIterator extends _GrowableMapIterator<String> {
  _GrowableMapKeyIterator(super._buffer, super._pointer);

  @override
  String get current => _currentKey;
}

class _GrowableMapValueIterator<V> extends _GrowableMapIterator<V> {
  _GrowableMapValueIterator(super._buffer, super._pointer);

  @override
  V get current => _currentValue as V;
}

class _GrowableMapEntryIterator<V>
    extends _GrowableMapIterator<MapEntry<String, V>> {
  _GrowableMapEntryIterator(super._buffer, super._pointer);

  @override
  MapEntry<String, V> get current => MapEntry(_currentKey, _currentValue as V);
}