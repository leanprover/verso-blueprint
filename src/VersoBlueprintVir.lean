/-
Copyright (c) 2026 Lean FRO LLC. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Emilio J. Gallego Arias
-/
module

public import Vir.Resources
public meta import Vir.Attributes

/-!
VIR support for Blueprint clients.

This entry exposes upstream resource values and export markers without loading
the browser runtime, React, or infoview. Runtime acquisition and application
programs remain explicit upstream VIR operations. The generated preview runtime
uses a shared, Lake-prepared program for external-markup selection and graph IDs.
-/
