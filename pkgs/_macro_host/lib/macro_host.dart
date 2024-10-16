// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:_macro_builder/macro_builder.dart';
import 'package:_macro_runner/macro_runner.dart';
import 'package:_macro_server/macro_server.dart';
import 'package:dart_model/dart_model.dart';
import 'package:macro_service/macro_service.dart';

/// Hosts macros: builds them, runs them, serves the macro service.
///
/// Tools that want to support macros, such as the Analyzer and the CFE, can
/// do so by running a `MacroHost` and providing their own `HostService`.
class MacroHost implements HostService {
  final MacroServer macroServer;
  final ListOfServices services;
  final MacroBuilder macroBuilder = MacroBuilder();
  final MacroRunner macroRunner = MacroRunner();

  // TODO(davidmorgan): this should be per macro, as part of tracking per-macro
  // lifecycle state.
  Completer<Set<int>>? _macroPhases;

  MacroHost._(this.macroServer, this.services) {
    services.services.insert(0, this);
  }

  /// Starts a macro host serving the provided [service].
  ///
  /// The service passed in should handle introspection RPCs, it does not need
  /// to handle others.
  ///
  /// TODO(davidmorgan): make this split clearer, it should be in the protocol
  /// definition somewhere which requests the host handles.
  static Future<MacroHost> serve({required HostService service}) async {
    final listOfServices = ListOfServices();
    listOfServices.services.add(service);
    final server = await MacroServer.serve(service: listOfServices);
    return MacroHost._(server, listOfServices);
  }

  /// Whether [name] is a macro according to that package's `pubspec.yaml`.
  bool isMacro(Uri packageConfig, QualifiedName name) {
    // TODO(language/3728): this is a placeholder, use package config when
    // available.
    return true;
  }

  /// Determines which phases the macro implemented at [name] runs in.
  Future<Set<int>> queryMacroPhases(
      Uri packageConfig, QualifiedName name) async {
    // TODO(davidmorgan): track macro lifecycle, correctly run once per macro
    // code change including if queried multiple times before response returns.
    if (_macroPhases != null) return _macroPhases!.future;
    _macroPhases = Completer();
    final macroBundle = await macroBuilder.build(packageConfig, [name]);
    macroRunner.start(macroBundle: macroBundle, endpoint: macroServer.endpoint);
    return _macroPhases!.future;
  }

  /// Sends [request] to the macro with [name].
  Future<AugmentResponse> augment(
      QualifiedName name, AugmentRequest request) async {
    // TODO(davidmorgan): this just assumes the macro is running, actually
    // track macro lifecycle.
    final response = await macroServer.sendToMacro(
        name, HostRequest.augmentRequest(request));
    return response.asAugmentResponse;
  }

  /// Handle requests that are for the host.
  @override
  Future<Response?> handle(MacroRequest request) async {
    switch (request.type) {
      case MacroRequestType.macroStartedRequest:
        _macroPhases!.complete(request
            .asMacroStartedRequest.macroDescription.runsInPhases
            .toSet());
        return Response.macroStartedResponse(MacroStartedResponse());
      default:
        return null;
    }
  }
}

// TODO(davidmorgan): this is used to handle some requests in the host while
// letting some fall through to the passed in service. Differentiate in a
// better way.
class ListOfServices implements HostService {
  List<HostService> services = [];

  @override
  Future<Response> handle(MacroRequest request) async {
    for (final service in services) {
      final result = await service.handle(request);
      if (result != null) return result;
    }
    throw StateError('No service handled: $request');
  }
}
