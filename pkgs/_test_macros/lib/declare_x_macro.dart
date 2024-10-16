// Copyright (c) 2024, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:dart_model/dart_model.dart';
import 'package:macro/macro.dart';
import 'package:macro_service/macro_service.dart';

/// Adds a getter `int get x` to the class.
class DeclareX {
  const DeclareX();
}

class DeclareXImplementation implements Macro {
  @override
  MacroDescription get description => MacroDescription(runsInPhases: [2]);

  @override
  Future<AugmentResponse> augment(Host host, AugmentRequest request) async {
    // TODO(davidmorgan): still need to pass through the augment target.
    return AugmentResponse(
        augmentations: [Augmentation(code: 'int get x => 3;')]);
  }
}
