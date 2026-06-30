import Foundation

/// Controllable feature toggles, mapped from the per-model `feature_variant_configs`
/// in the Smart Control APK. The UI shows only the features the connected model has.
enum Feature: CaseIterable {
    case equalizer, sidetone, autoPowerOff, podcastMode, voicePrompts
    case autoAnswer, comfortCall, smartPause, onHeadDetection
    case lowLatency, btCompatibility
    case connectionManagement, factoryReset, productInfo
}

/// What a specific Sennheiser model supports — drives which controls are shown.
struct DeviceProfile {
    let displayName: String
    let features: Set<Feature>
    let noiseVariant: Int        // 1 = ANC on/off + transparency toggle; 2 = adaptive/custom
    let transparencySteps: Int   // 1 = on/off only (no level slider); >1 = level slider
    let hasTransparency: Bool
    let hasAntiWind: Bool

    func has(_ f: Feature) -> Bool { features.contains(f) }
    var showsTransparencyLevel: Bool { hasTransparency && transparencySteps > 1 }

    // MARK: - Known models (derived from acc1 / accPlus1 / accTw1 configs)

    /// ACCENTUM Wireless — model id prefix `ACAEBT`. NoiseControl variant 1, 1-step transparency.
    static let accentumWireless = DeviceProfile(
        displayName: "ACCENTUM Wireless",
        features: [.equalizer, .sidetone, .autoPowerOff, .podcastMode, .voicePrompts,
                   .connectionManagement, .factoryReset, .productInfo],
        noiseVariant: 1, transparencySteps: 1, hasTransparency: true, hasAntiWind: true)

    /// ACCENTUM Plus — model id prefix `ACPAEBT`. NoiseControl variant 2, adds calls/wear sensing.
    static let accentumPlus = DeviceProfile(
        displayName: "ACCENTUM Plus",
        features: [.equalizer, .sidetone, .autoPowerOff, .podcastMode, .voicePrompts,
                   .autoAnswer, .comfortCall, .smartPause, .onHeadDetection,
                   .connectionManagement, .factoryReset, .productInfo],
        noiseVariant: 2, transparencySteps: 3, hasTransparency: true, hasAntiWind: true)

    /// ACCENTUM True Wireless — earbuds; adds wear sensing & calls.
    static let accentumTrueWireless = DeviceProfile(
        displayName: "ACCENTUM True Wireless",
        features: [.equalizer, .sidetone, .autoPowerOff, .podcastMode, .voicePrompts,
                   .autoAnswer, .smartPause, .onHeadDetection,
                   .connectionManagement, .factoryReset, .productInfo],
        noiseVariant: 1, transparencySteps: 3, hasTransparency: true, hasAntiWind: true)

    /// Fallback for unknown / other Sennheiser GAIA models — show everything.
    static let permissive = DeviceProfile(
        displayName: "Sennheiser",
        features: Set(Feature.allCases),
        noiseVariant: 1, transparencySteps: 5, hasTransparency: true, hasAntiWind: true)

    /// Pick a profile from the model id (e.g. "ACAEBT White") and BT name.
    static func resolve(modelId: String, name: String) -> DeviceProfile {
        let id = modelId.uppercased()
        let nm = name.uppercased()
        if id.hasPrefix("ACPAEBT") || nm.contains("PLUS") { return accentumPlus }
        if id.hasPrefix("ACAEBT") || nm == "ACCENTUM" || nm.contains("ACCENTUM WIRELESS") { return accentumWireless }
        if id.contains("TW") || nm.contains("TRUE WIRELESS") { return accentumTrueWireless }
        return permissive
    }
}
