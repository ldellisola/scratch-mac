import ScratchCore

// Swift 6.2's Testing library has an `Attachment` of its own, so the bare name is ambiguous in a test file that imports
// both. Declared here, in the test module, this one wins in every test file.
typealias Attachment = ScratchCore.Attachment
