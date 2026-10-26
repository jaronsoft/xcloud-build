import SwiftUI

struct DecisionView: View {
    let shareToken: String
    @EnvironmentObject private var session: BmbSession
    @Environment(\.dismiss) private var dismiss
    @State private var decision: BmbDecision?
    @State private var comment = ""
    @State private var suggestedURL = ""
    @State private var reportReason = ""
    @State private var showingReport = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            if let decision {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text(decision.Status == "open" ? "OPEN DECISION" : "CLOSED DECISION")
                            .font(.caption.bold()).tracking(2).foregroundStyle(.green)
                        Spacer()
                        ShareLink(item: URL(string: decision.ShareUrl)!) {
                            Label("Share", systemImage: "square.and.arrow.up").font(.caption.bold())
                        }
                    }
                    Text(decision.Question).font(.system(size: 33, weight: .black, design: .rounded)).tracking(-1.6)
                    ForEach(Array(decision.Products.enumerated()), id: \.offset) { index, product in
                        BmbProductCard(product: product, label: decision.Mode == "pick_one" ? (index == 0 ? "A" : "B") : nil)
                    }
                    BmbCard {
                        VStack(alignment: .leading, spacing: 15) {
                            Text("THE VERDICT").font(.caption.bold()).tracking(2).foregroundStyle(.green)
                            Text("Your vote").font(.title2.bold())
                            Text("Voting is open to everyone. Sign in to add a reason.")
                                .font(.caption).foregroundStyle(BmbTheme.muted)
                            ForEach(voteChoices, id: \.0) { key, label in
                                Button { Task { await vote(key) } } label: {
                                    HStack {
                                        Text(label).fontWeight(.bold)
                                        Spacer()
                                        Text("\(decision.Votes[key] ?? 0)").fontWeight(.bold)
                                    }.padding(15)
                                        .background(key == "pass" || key == "b" ? Color.orange.opacity(0.12) : Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                                }
                                .buttonStyle(.plain).disabled(decision.Status != "open")
                            }
                            Text("\(decision.VoteCount) votes").font(.caption).foregroundStyle(BmbTheme.muted)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if decision.IsOwner && decision.Status == "open" {
                        BmbCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("My final choice").font(.headline)
                                HStack {
                                    ForEach(finalChoices, id: \.0) { key, label in
                                        Button(label) { Task { await finalize(key) } }
                                            .font(.caption.bold()).padding(8)
                                            .background(BmbTheme.paper, in: RoundedRectangle(cornerRadius: 9))
                                    }
                                }
                            }
                        }
                    }
                    if let choice = decision.FinalChoice {
                        Label("Final choice: \(choice)", systemImage: "checkmark.seal")
                            .font(.subheadline.bold()).foregroundStyle(.green)
                    }
                    BmbCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("Advice from friends").font(.headline)
                            ForEach(decision.Comments) { item in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.Body).font(.subheadline)
                                    if item.Status == "pending" { Text("Awaiting review").font(.caption).foregroundStyle(BmbTheme.muted) }
                                }.padding(.vertical, 7)
                                Divider()
                            }
                            if decision.Status == "open" {
                                TextField("What would you tell a friend?", text: $comment, axis: .vertical)
                                    .lineLimit(2...5).textFieldStyle(.roundedBorder)
                                TextField("Alternative product URL (optional)", text: $suggestedURL)
                                    .textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
                                Button("Send for review") { Task { await submitComment() } }
                                    .font(.subheadline.bold()).disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(.orange) }
                    Button("Report this decision") {
                        if session.isLoggedIn { showingReport = true } else { session.showLogin = true }
                    }.font(.caption).foregroundStyle(BmbTheme.muted)
                }.padding(20)
            } else { ProgressView().frame(maxWidth: .infinity, minHeight: 300) }
        }
        .background(BmbTheme.paper)
        .navigationTitle("Decision")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        .task(id: shareToken) { await load() }
        .alert("Report this decision", isPresented: $showingReport) {
            TextField("Reason", text: $reportReason)
            Button("Send") { Task { await report() } }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var voteChoices: [(String, LocalizedStringKey)] {
        decision?.Mode == "pick_one" ? [("a", "Option A"), ("b", "Option B")] : [("buy", "Buy it"), ("pass", "Pass")]
    }
    private var finalChoices: [(String, LocalizedStringKey)] {
        [("bought", "Bought"), ("passed", "Passed"), ("switched", "Switched"), ("waiting", "Waiting")]
    }
    private func load() async {
        do { decision = try await session.api.detail(shareToken, token: session.token) }
        catch { message = error.localizedDescription }
    }
    private func vote(_ choice: String) async {
        do { try await session.api.vote(shareToken, choice: choice); await load() }
        catch { message = error.localizedDescription }
    }
    private func finalize(_ choice: String) async {
        guard let token = session.token else { session.showLogin = true; return }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/d/\(shareToken)/final-choice", method: "POST", body: ["Choice": choice], token: token)
            await load()
        } catch { message = error.localizedDescription }
    }
    private func submitComment() async {
        guard let token = session.token else { session.showLogin = true; return }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/d/\(shareToken)/comments", method: "POST",
                body: ["Body": comment, "SuggestedUrl": suggestedURL], token: token)
            comment = ""; suggestedURL = ""; message = String(localized: "Your comment is awaiting review.")
            await load()
        } catch { message = error.localizedDescription }
    }
    private func report() async {
        guard let token = session.token else { session.showLogin = true; return }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/d/\(shareToken)/reports", method: "POST", body: ["Reason": reportReason], token: token)
            message = String(localized: "Report sent")
        } catch { message = error.localizedDescription }
    }
}
