import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var store: MosaStore
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Eyebrow(text: "MOSA")
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(0..<40, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 7)
                            .fill(index % 5 == 4 ? MosaPalette.paperSecondary : MosaPalette.dayColors[index % 5])
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .frame(maxWidth: 390)

                Text("Your days become a life you can see.")
                    .font(.system(size: 44, weight: .medium, design: .serif))
                    .minimumScaleFactor(0.8)
                Text("Record a color or a thought. MOSA turns each day into a quiet, lasting canvas.")
                    .font(.title3)
                    .foregroundStyle(MosaPalette.muted)
                    .lineSpacing(6)

                if let notice = store.notice {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(notice, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(MosaPalette.navy)
                        Button("Dismiss") { store.notice = nil }
                            .font(.caption.bold())
                    }
                    .mosaCard()
                }

                NavigationLink(destination: OnboardingView()) {
                    Text("Begin on this device")
                }
                .buttonStyle(MosaPrimaryButtonStyle())

                NavigationLink(destination: AuthView()) {
                    Text("Sign in or create an account")
                }
                .buttonStyle(MosaSecondaryButtonStyle())

                Text("You can explore privately and offline. An account is only needed when you choose to save to the cloud.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MosaPalette.muted)
                    .frame(maxWidth: .infinity)
                CompanyFooter().frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .navigationBarBackButtonHidden()
        .mosaPage()
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var store: MosaStore
    @State private var displayName = ""
    @State private var startYear = Calendar.current.component(.year, from: .now)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: "First setting")
                Text("Where should your canvas begin?")
                    .font(.system(size: 42, weight: .medium, design: .serif))
                Text("This sets the first year you can revisit. You can change it later.")
                    .foregroundStyle(MosaPalette.muted)

                VStack(alignment: .leading, spacing: 18) {
                    TextField("How should MOSA greet you?", text: $displayName)
                        .textContentType(.name)
                        .textFieldStyle(.roundedBorder)
                    Picker("Start year", selection: $startYear) {
                        ForEach(Array((Calendar.current.component(.year, from: .now) - 110)...Calendar.current.component(.year, from: .now)).reversed(), id: \.self) { Text(String($0)).tag($0) }
                    }
                    .pickerStyle(.menu)
                    LabeledContent("Language", value: "English")
                    Button("Create my canvas") {
                        store.setup(displayName: displayName, startYear: startYear)
                    }
                    .buttonStyle(MosaPrimaryButtonStyle())
                }
                .mosaCard()
                CompanyFooter().frame(maxWidth: .infinity).padding(.top, 20)
            }
            .padding(24)
        }
        .navigationTitle("Set up MOSA")
        .navigationBarTitleDisplayMode(.inline)
        .mosaPage()
    }
}
