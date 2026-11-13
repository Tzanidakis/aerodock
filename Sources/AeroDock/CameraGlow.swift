import SwiftUI

/// Only a narrow outline outside the camera housing; never a second island.
struct CameraGlow: View {
    @ObservedObject var model: IslandModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20, paused: !model.cameraGlowVisible || reduceMotion)) { timeline in
            let pulse = reduceMotion ? 0.85 : 0.78 + 0.18 * sin(timeline.date.timeIntervalSinceReferenceDate * 2)
            let outline = UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 11,
                                                 bottomTrailingRadius: 11, topTrailingRadius: 0)
            outline.stroke(model.activityColor, lineWidth: 2)
                .shadow(color: model.activityColor.opacity(0.8), radius: 3)
                .opacity(pulse)
                .padding(3)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
