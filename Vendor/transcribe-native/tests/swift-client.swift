import Foundation
import VoicePenGigaAM

var load = transcribe_model_load_params()
transcribe_model_load_params_init(&load)
precondition(load.struct_size == MemoryLayout<transcribe_model_load_params>.size)
precondition(String(cString: transcribe_version()) == "0.4.0")
var invalid = transcribe_model_load_params()
var model: OpaquePointer?
let status = transcribe_model_load_file("/missing-model.gguf", &invalid, &model)
precondition(status == TRANSCRIBE_ERR_BAD_STRUCT_SIZE)
precondition(model == nil)
print("Swift C ABI import/defaults/incompatible-interface smoke passed")
