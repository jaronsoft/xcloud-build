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
                        NavigationLink {
                            BmbDecisionShareView(decision: decision)
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up").font(.caption.bold())
                        }
                    }
                    if decision.IsOwner && decision.Visibility == "public" {
                        Text(LocalizedStringKey(decision.PublicReviewStatus == "approved" ? "Visible in Explore" :
                            decision.PublicReviewStatus == "rejected" ? "Explore submission declined" : "Awaiting Explore review"))
                            .font(.caption.bold()).foregroundStyle(BmbTheme.muted)
                    }
                    Text(decision.Question).font(.system(size: 33, weight: .black, design: .rounded)).tracking(-1.6)
                    ForEach(Array(decision.Products.enumerated()), id: \.offset) { index, product in
                        BmbProductCard(product: product, label: decision.Mode == "pick_one" ? (index == 0 ? "A" : "B") : nil)
                        PriceOfferSection(shareToken: shareToken, product: product,
                            offers: decision.PriceOffers.filter { $0.ProductId == product.Id },
                            isOwner: decision.IsOwner, isOpen: decision.Status == "open", reload: load)
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
                            Text("Advice from others").font(.headline)
                            ForEach(decision.Comments) { item in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.Body).font(.subheadline)
                                    if item.Status == "pending" { Text("Awaiting review").font(.caption).foregroundStyle(BmbTheme.muted) }
                                }.padding(.vertical, 7)
                                Divider()
                            }
                            if decision.Status == "open" {
                                TextField("What would you suggest?", text: $comment, axis: .vertical)
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
        .task(id: shareToken) {
            decision = await session.api.cached("/d/\(shareToken)", token: session.token)
            await load()
        }
        .refreshable { await load() }
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

private struct PriceOfferSection: View {
    let shareToken: String
    let product: BmbProduct
    let offers: [BmbPriceOffer]
    let isOwner: Bool
    let isOpen: Bool
    let reload: () async -> Void
    @EnvironmentObject private var session: BmbSession
    @State private var target: String
    @State private var site = ""
    @State private var country = ""
    @State private var price = ""
    @State private var currency: String
    @State private var url = ""
    @State private var note = ""
    @State private var message: String?

    init(shareToken: String, product: BmbProduct, offers: [BmbPriceOffer], isOwner: Bool, isOpen: Bool, reload: @escaping () async -> Void) {
        self.shareToken = shareToken; self.product = product; self.offers = offers
        self.isOwner = isOwner; self.isOpen = isOpen; self.reload = reload
        _target = State(initialValue: product.TargetPrice.map { String($0) } ?? "")
        _currency = State(initialValue: product.Currency ?? BmbCurrency.defaultCode)
    }

    var body: some View {
        BmbCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Price tips for this product").font(.headline)
                Text("Price when posted").font(.subheadline.bold())
                Text(product.Price.map { "\(product.Currency ?? "") \($0)" } ?? "—").font(.subheadline)
                if let captured = product.CapturedAt { Text(captured).font(.caption).foregroundStyle(BmbTheme.muted) }
                Text("Price I would accept").font(.subheadline.bold())
                Text(product.TargetPrice.map { "\(product.Currency ?? "") \($0)" } ?? "—").font(.subheadline)
                if isOwner && isOpen {
                    TextField("Edit target price; clear to remove", text: $target).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    Button("Save target") { Task { await saveTarget() } }
                        .disabled(product.Currency == nil)
                }
                ForEach(offers) { offer in
                    Divider()
                    Text("\(offer.SiteName) · \(offer.CountryCode) · \(offer.Currency) \(offer.Price)").font(.subheadline.bold())
                    if offer.MeetsTarget {
                        Text("Meets target").font(.caption.bold()).foregroundStyle(.green)
                    }
                    HStack {
                        Text("User reported")
                        Text("· \(offer.CreateTime)")
                        if offer.Status == "pending" { Text("· Awaiting review") }
                    }.font(.caption).foregroundStyle(BmbTheme.muted)
                    if let note = offer.Note { Text(note).font(.caption) }
                    if let url = offer.Url, let link = URL(string: url) { Link("View product", destination: link) }
                }
                if isOpen {
                    Divider()
                    Text("Share a price you found").font(.subheadline.bold())
                    TextField("Website", text: $site).textFieldStyle(.roundedBorder)
                    TextField("Country or region code (US)", text: $country).textInputAutocapitalization(.characters).textFieldStyle(.roundedBorder)
                    TextField("Price", text: $price).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    Picker("Currency", selection: $currency) {
                        ForEach(BmbCurrency.codes, id: \.self) { code in Text(BmbCurrency.label(code)).tag(code) }
                    }
                    TextField("Product URL (optional)", text: $url).textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
                    TextField("Shipping, tax, or conditions (optional)", text: $note, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                    Button(session.isLoggedIn ? "Send price for review" : "Sign in to share") { Task { await submit() } }
                        .disabled(site.trimmingCharacters(in: .whitespaces).isEmpty || country.count != 2 || Double(price) == nil)
                }
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            }
        }
        .onChange(of: product.TargetPrice) { _, value in target = value.map { String($0) } ?? "" }
    }

    private func saveTarget() async {
        guard let token = session.token else { session.showLogin = true; return }
        guard let id = product.Id else { return }
        do {
            let body: [String: Any] = ["TargetPrice": Double(target) as Any? ?? NSNull(), "TargetCurrency": product.Currency ?? ""]
            let _: BmbAcknowledgement = try await session.api.call("/d/\(shareToken)/products/\(id)/target-price", method: "PUT", body: body, token: token)
            message = String(localized: "Target price updated")
            await reload()
        } catch { message = error.localizedDescription }
    }

    private func submit() async {
        guard let token = session.token else { session.showLogin = true; return }
        guard let id = product.Id, let amount = Double(price) else { return }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/d/\(shareToken)/price-offers", method: "POST", body: [
                "ProductId": id, "SiteName": site, "CountryCode": country.uppercased(), "Price": amount,
                "Currency": currency, "Url": url, "Note": note
            ], token: token)
            site = ""; country = ""; price = ""; url = ""; note = ""
            message = String(localized: "Price submitted for review")
            await reload()
        } catch { message = error.localizedDescription }
    }
}
