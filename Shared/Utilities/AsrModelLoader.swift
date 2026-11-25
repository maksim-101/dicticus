/// Engine-free namespace shared by both platforms' ASR model loaders (Phase 47.1,
/// D-04 engine swap). macOS hangs `loadWhisperKit`/`modelName` off this type via
/// `macOS/Dicticus/Utilities/AsrModelLoader+WhisperKit.swift`; iOS hangs
/// `loadFluidAudio`/`parakeetModelName` off it via
/// `iOS/Dicticus/Utilities/AsrModelLoader+FluidAudio.swift`. Nothing genuinely
/// cross-platform remains after the split — this bare declaration exists so both
/// platform extensions have a shared type to extend.
enum AsrModelLoader {}
