// NLInterpreter.swift — the on-device natural-language → ActionRequests bridge, backed by Apple's
// FoundationModels (the system on-device LLM). Availability-gated three ways: compiled only when the
// SDK is present (`canImport`), runtime `@available(macOS 26)`, and `SystemLanguageModel.default
// .availability` (Apple Intelligence must be enabled + the model downloaded). The model fills a
// @Generable command list shaped by NLCommand's catalog prompt; we map it back to ActionRequests via
// the shared parser (NLCommand.requests), dropping anything invalid. No AX. Gated [nl] enabled.

import Foundation
import ZTCore

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum NLInterpreter {
    public enum Status: Equatable { case available, unavailable(String) }
    /// Plain outcome (Swift.Result requires Failure: Error; a String reason is friendlier here).
    public enum Outcome: Equatable { case requests([ActionRequest]); case error(String) }

    /// Whether the on-device model can be used right now (SDK present + OS + Apple Intelligence on).
    public static var status: Status {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let a = SystemLanguageModel.default.availability
            if case .available = a { return .available }
            return .unavailable("on-device model not ready: \(a)")
        } else { return .unavailable("requires macOS 26") }
        #else
        return .unavailable("FoundationModels SDK not available in this build")
        #endif
    }

    /// Interpret `text` into ActionRequests using `systemPrompt` (build it from
    /// NLCommand.systemPrompt(catalog:)). Returns .failure with a human reason when the model is
    /// unavailable or generation fails.
    public static func interpret(_ text: String, systemPrompt: String) async -> Outcome {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let a = SystemLanguageModel.default.availability
            guard case .available = a else { return .error("on-device model unavailable: \(a)") }
            do {
                let session = LanguageModelSession(instructions: systemPrompt)
                let response = try await session.respond(to: text, generating: NLPlan.self)
                let cmds = response.content.commands.map { (action: $0.action, params: $0.params()) }
                return .requests(NLCommand.requests(from: cmds))
            } catch {
                return .error("generation failed: \(error.localizedDescription)")
            }
        } else { return .error("requires macOS 26") }
        #else
        return .error("FoundationModels SDK not available in this build")
        #endif
    }
}

#if canImport(FoundationModels)
@available(macOS 26.0, *)
@Generable
struct NLPlan {
    let commands: [NLPlanCmd]
}

@available(macOS 26.0, *)
@Generable
struct NLPlanCmd {
    let action: String          // an action name from the prompt's allowed list
    let zone: String?           // zone key, if the action needs one
    let direction: String?      // next/previous/up/down/left/right, if needed
    let name: String?           // layout/cluster name, if needed
    let app: String?            // app name, if needed

    func params() -> [String: String] {
        var p: [String: String] = [:]
        if let zone, !zone.isEmpty { p["zone"] = zone }
        if let direction, !direction.isEmpty { p["direction"] = direction }
        if let name, !name.isEmpty { p["name"] = name }
        if let app, !app.isEmpty { p["app"] = app }
        return p
    }
}
#endif
