import SwiftUI

/// The one question Entrain asks on first launch, and the only thing it
/// does with the answer is set the default intensity.
///
/// Medium is right for most people and wrong for the listener who
/// under-responds to ordinary background stimulation: for them the medium
/// bed is a sound that is simply there, doing nothing, and the app is a
/// thing they tried once. Asking costs one screen and a tap to skip, and it
/// is the difference between that listener finding Strong and never knowing
/// it exists. It is a question about sound, in the words someone would use
/// about sound — no diagnosis, no screener, and no claim about anybody.
struct IntensityQuestion: View {
    let answer: (Intensity?) -> Void
    @State private var choice: Intensity?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How does background sound work for you?")
                            .font(.title2.weight(.semibold))
                        Text("Entrain's sound pulses gently. How strong that pulse should be is different for everyone, so pick what sounds like you. You can change it any time in Settings.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 32)

                    VStack(spacing: 10) {
                        ForEach(Intensity.allCases) { intensity in
                            Choice(intensity: intensity, selected: choice == intensity) {
                                choice = intensity
                            }
                        }
                    }
                }
                .frame(maxWidth: 420)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 12) {
                Button {
                    answer(choice)
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Mode.relax.tint)
                .foregroundStyle(Mode.relax.onTint)
                .disabled(choice == nil)

                Button("Skip") { answer(nil) }
                    .font(.subheadline)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 420)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(QuestionBackdrop())
        .preferredColorScheme(.dark)
    }
}

/// One answer. The label is the sentence; the setting it maps to is shown
/// beside it, so the question and the Intensity control in Settings are
/// visibly the same thing rather than two settings that happen to agree.
private struct Choice: View {
    let intensity: Intensity
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                Text(intensity.blurb)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Text(intensity.title)
                    .font(.caption.weight(.semibold))
                    .opacity(0.7)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .opacity(selected ? 1 : 0.4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .glassEffect(
            selected ? .regular.tint(Mode.relax.tint).interactive() : .regular.interactive(),
            in: .rect(cornerRadius: 18)
        )
        .foregroundStyle(selected ? Mode.relax.onTint : .primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The player's night gradient, without a mode to warm it.
private struct QuestionBackdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.07, green: 0.06, blue: 0.20), Color(red: 0.03, green: 0.13, blue: 0.18)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
