# Apple Foundation Models Documentation

## This page requires JavaScript.

**URL:** https://developer.apple.com/documentation/SwiftUI/View/backgroundExtensionEffect()

SwiftUI  View  backgroundExtensionEffect() Instance MethodbackgroundExtensionEffect()Adds the background extension effect to the view. The view will be duplicated into mirrored copies which will be placed around the view on any edge with available safe area. Additionally, a blur effect will be applied on top to blur out the copies.iOS 26.0+iPadOS 26.0+Mac Catalyst 26.0+macOS 26.0+tvOS 26.0+visionOS 26.0+watchOS 26.0+@MainActor @preconcurrency
func backgroundExtensionEffect() -> some View
DiscussionUse this modifier when you want to extend the view beyond its bounds so the copies can function as backgrounds for other elements on top. The most common use case is to apply this to a view in the detail column of a navigation split view so it can extend under the sidebar or inspector region to provide seamless immersive visuals.NavigationSplitView {
    // sidebar content
} detail: {
    ZStack {
        BannerView()
            .backgroundExtensionEffect()
    }
}
.inspector(isPresented: $showInspector) {
    // inspector content
}
Apply this modifier with discretion. This should often be used with only a single instance of background content with consideration of visual clarity and performance.NoteThis modifier will clip the view to prevent copies from overlapping with each other. Current page is backgroundExtensionEffect()

### Related Links

- [Documentation](https://developer.apple.com/documentation/)
- [Sample Code](https://developer.apple.com/documentation/samplecode/)
- [Documentation](https://developer.apple.com/documentation)
- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
- [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui)
- [Landmarks: Building an app with Liquid Glass](https://developer.apple.com/documentation/swiftui/landmarks-building-an-app-with-liquid-glass)
- [App organization](https://developer.apple.com/documentation/swiftui/app-organization)
- [Scenes](https://developer.apple.com/documentation/swiftui/scenes)
- [Windows](https://developer.apple.com/documentation/swiftui/windows)
- [Immersive spaces](https://developer.apple.com/documentation/swiftui/immersive-spaces)
- [Documents](https://developer.apple.com/documentation/swiftui/documents)
- [Navigation](https://developer.apple.com/documentation/swiftui/navigation)
- [Modal presentations](https://developer.apple.com/documentation/swiftui/modal-presentations)
- [Toolbars](https://developer.apple.com/documentation/swiftui/toolbars)
- [Search](https://developer.apple.com/documentation/swiftui/search)
- [App extensions](https://developer.apple.com/documentation/swiftui/app-extensions)
- [Model data](https://developer.apple.com/documentation/swiftui/model-data)
- [Environment values](https://developer.apple.com/documentation/swiftui/environment-values)
- [Preferences](https://developer.apple.com/documentation/swiftui/preferences)
- [func addPassToWalletButtonStyle(AddPassToWalletButtonStyle) -> some View](https://developer.apple.com/documentation/swiftui/view/addpasstowalletbuttonstyle(_:))
- [func allowsWindowActivationEvents() -> some View](https://developer.apple.com/documentation/swiftui/view/allowswindowactivationevents())
- [func allowsWindowActivationEvents() -> some View](https://developer.apple.com/documentation/swiftui/view/allowswindowactivationevents())
- [func appStoreMerchandising(isPresented: Binding<Bool>, kind: AppStoreMerchandisingKind, onDismiss: ((Result<AppStoreMerchandisingKind.PresentationResult, any Error>) async -> ())?) -> some View](https://developer.apple.com/documentation/swiftui/view/appstoremerchandising(ispresented:kind:ondismiss:))
- [func appStoreMerchandising(isPresented: Binding<Bool>, kind: AppStoreMerchandisingKind, onDismiss: ((Result<AppStoreMerchandisingKind.PresentationResult, any Error>) async -> ())?) -> some View](https://developer.apple.com/documentation/swiftui/view/appstoremerchandising(ispresented:kind:ondismiss:))
- [func aspectRatio3D(Size3D?, contentMode: ContentMode) -> some View](https://developer.apple.com/documentation/swiftui/view/aspectratio3d(_:contentmode:))
- [func assistiveAccessNavigationIcon(Image) -> some View](https://developer.apple.com/documentation/swiftui/view/assistiveaccessnavigationicon(_:))
- [func assistiveAccessNavigationIcon(systemImage: String) -> some View](https://developer.apple.com/documentation/swiftui/view/assistiveaccessnavigationicon(systemimage:))
- [func attributedTextFormattingDefinition(_:)](https://developer.apple.com/documentation/swiftui/view/attributedtextformattingdefinition(_:))
- [func automatedDeviceEnrollmentAddition(isPresented: Binding<Bool>) -> some View](https://developer.apple.com/documentation/swiftui/view/automateddeviceenrollmentaddition(ispresented:))
- [func backgroundExtensionEffect() -> some View](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect())
- [func backgroundExtensionEffect(isEnabled: Bool) -> some View](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect(isenabled:))
- [func breakthroughEffect(BreakthroughEffect) -> some View](https://developer.apple.com/documentation/swiftui/view/breakthrougheffect(_:))
- [func buttonSizing(ButtonSizing) -> some View](https://developer.apple.com/documentation/swiftui/view/buttonsizing(_:))
- [func certificateSheet(trust: Binding<SecTrust?>, title: String?, message: String?, help: URL?) -> some View](https://developer.apple.com/documentation/swiftui/view/certificatesheet(trust:title:message:help:))
- [func chart3DCameraProjection(Chart3DCameraProjection) -> some View](https://developer.apple.com/documentation/swiftui/view/chart3dcameraprojection(_:))
- [func chart3DPose(_:)](https://developer.apple.com/documentation/swiftui/view/chart3dpose(_:))
- [func chart3DRenderingStyle(Chart3DRenderingStyle) -> some View](https://developer.apple.com/documentation/swiftui/view/chart3drenderingstyle(_:))
- [func chartZAxis(Visibility) -> some View](https://developer.apple.com/documentation/swiftui/view/chartzaxis(_:))
- [func chartZAxis<Content>(content: () -> Content) -> some View](https://developer.apple.com/documentation/swiftui/view/chartzaxis(content:))
- [func chartZAxisLabel(_:position:alignment:spacing:)](https://developer.apple.com/documentation/swiftui/view/chartzaxislabel(_:position:alignment:spacing:))
- [func chartZScale<Domain, Range>(domain: Domain, range: Range, type: ScaleType?) -> some View](https://developer.apple.com/documentation/swiftui/view/chartzscale(domain:range:type:))
- [func chartZScale<Domain>(domain: Domain, type: ScaleType?) -> some View](https://developer.apple.com/documentation/swiftui/view/chartzscale(domain:type:))
- [func chartZScale<Range>(range: Range, type: ScaleType?) -> some View](https://developer.apple.com/documentation/swiftui/view/chartzscale(range:type:))
- [func chartZSelection<P>(range: Binding<ClosedRange<P>?>) -> some View](https://developer.apple.com/documentation/swiftui/view/chartzselection(range:))
- [func chartZSelection<P>(value: Binding<P?>) -> some View](https://developer.apple.com/documentation/swiftui/view/chartzselection(value:))
- [func contactAccessButtonCaption(ContactAccessButton.Caption) -> some View](https://developer.apple.com/documentation/swiftui/view/contactaccessbuttoncaption(_:))
- [func contactAccessButtonStyle(ContactAccessButton.Style) -> some View](https://developer.apple.com/documentation/swiftui/view/contactaccessbuttonstyle(_:))
- [func contactAccessPicker(isPresented: Binding<Bool>, completionHandler: ([String]) -> ()) -> some View](https://developer.apple.com/documentation/swiftui/view/contactaccesspicker(ispresented:completionhandler:))
- [func containerCornerOffset(Edge.Set, sizeToFit: Bool) -> some View](https://developer.apple.com/documentation/swiftui/view/containercorneroffset(_:sizetofit:))
- [func containerValue<V>(WritableKeyPath<ContainerValues, V>, V) -> some View](https://developer.apple.com/documentation/swiftui/view/containervalue(_:_:))
- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [View](https://developer.apple.com/documentation/swiftui/view)
- [MainActor](https://developer.apple.com/documentation/Swift/MainActor)
- [View](https://developer.apple.com/documentation/swiftui/view)
- [Discussion](https://developer.apple.com/documentation/SwiftUI/View/backgroundExtensionEffect()#discussion)
- [Documentation](https://developer.apple.com/documentation/)
- [Documentation](https://developer.apple.com/documentation/)

---

