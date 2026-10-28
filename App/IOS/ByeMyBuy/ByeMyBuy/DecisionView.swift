import SwiftUI

struct DecisionView: View {
    let shareToken: String
    @EnvironmentObject private var session: BmbSession
    @Environment(\.dismiss) private var dismiss
    @State private var decision: BmbDecision?
    @State private var comment = ""
    @State private var voteReasons: [String: String] = [:]
    @State private var suggestedURL = ""
    @State private var reportReason = ""
    @State private var showingReport = false
    @State private var message: String?

    var body: some View {
        GeometryReader { geometry in
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
                    BmbDecisionQuestion(question: decision.Question)
                        .id(decision.Id)
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
                                let reasons = key == "buy" ? ["useful","value","quality"] : key == "pass" ? ["expensive","duplicate","wait"] : ["value","fit","quality"]
                                Picker(BmbEngagementCopy.text("Reason (optional)", "理由（可选）"), selection: Binding(get: { voteReasons[key] ?? "" }, set: { voteReasons[key] = $0 })) {
                                    Text("—").tag("")
                                    ForEach(reasons, id: \.self) { reason in Text(BmbEngagementCopy.reason(reason)).tag(reason) }
                                }
                                Button { Task { await vote(key) } } label: {
                                    HStack {
                                        Text(label).fontWeight(.bold)
                                        Spacer()
                                        Text("\(decision.Votes[key] ?? 0)").fontWeight(.bold)
                                        Text("\(decision.VoteCount == 0 ? 0 : Int(Double(decision.Votes[key] ?? 0) / Double(decision.VoteCount) * 100))%")
                                    }.padding(15)
                                        .background(key == "pass" || key == "b" ? Color.orange.opacity(0.12) : Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                                }
                                .buttonStyle(.plain).disabled(decision.Status != "open")
                                ForEach((decision.VoteReasons?[key] ?? [:]).keys.sorted(), id: \.self) { reason in
                                    Text("\(BmbEngagementCopy.reason(reason)): \(decision.VoteReasons?[key]?[reason] ?? 0)").font(.caption)
                                }
                            }
                            Text("\(decision.VoteCount) votes").font(.caption).foregroundStyle(BmbTheme.muted)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(Array(decision.Products.enumerated()), id: \.offset) { _, product in
                        PriceOfferSection(shareToken: shareToken, product: product,
                            offers: decision.PriceOffers.filter { $0.ProductId == product.Id },
                            isOwner: decision.IsOwner, isOpen: decision.Status == "open", reload: load)
                    }
                    BmbDecisionTools(item: decision, reload: load)
                    if let choice = decision.FinalChoice {
                        Label("Final choice: \(choice)", systemImage: "checkmark.seal")
                            .font(.subheadline.bold()).foregroundStyle(.green)
                    }
                    BmbCard {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("Advice from others").font(.headline)
                            ForEach(decision.Comments) { item in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.Body).font(.subheadline).fixedSize(horizontal: false, vertical: true)
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
                }.frame(width: max(0, geometry.size.width - 40), alignment: .leading).padding(20)
            } else { ProgressView().frame(maxWidth: .infinity, minHeight: 300) }
        }
        }
        .background(BmbTheme.paper)
        .navigationTitle("Decision")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        .task(id: shareToken) {
            await session.api.track("decision_viewed", shareToken: shareToken, token: session.token)
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
        do {
            let _: BmbAcknowledgement = try await session.api.call("/d/\(shareToken)/votes", method: "POST", body: ["Choice": choice, "Reason": voteReasons[choice] as Any? ?? NSNull()], token: session.token)
            await load()
        }
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

private struct BmbDecisionQuestion: View {
    let question: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if expanded {
                Text(question).font(.body).fixedSize(horizontal: false, vertical: true)
                toggle
            } else {
                // 用完整单行的实际宽度选择布局，短问题不显示多余的展开入口。
                ViewThatFits(in: .horizontal) {
                    Text(question.split(whereSeparator: \.isWhitespace).joined(separator: " "))
                        .font(.title3.bold()).lineLimit(1).fixedSize()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(question).font(.title3.bold()).lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        toggle
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: question) { _, _ in expanded = false }
    }

    private var toggle: some View {
        Button {
            expanded.toggle()
        } label: {
            Text(BmbEngagementCopy.text(expanded ? "Show less" : "Read more", expanded ? "收起全文" : "展开全文"))
                .font(.subheadline.bold()).underline().frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded ? BmbEngagementCopy.text("Expanded", "已展开") : BmbEngagementCopy.text("Collapsed", "已收起"))
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
    @State private var model = ""
    @State private var country = ""
    @State private var price = ""
    @State private var currency: String
    @State private var url = ""
    @State private var note = ""
    @State private var message: String?

    init(shareToken: String, product: BmbProduct, offers: [BmbPriceOffer], isOwner: Bool, isOpen: Bool, reload: @escaping () async -> Void) {
        self.shareToken = shareToken; self.product = product; self.offers = offers
        self.isOwner = isOwner; self.isOpen = isOpen; self.reload = reload
        _target = State(initialValue: product.TargetPrice.map { BmbMoney.number($0) } ?? "")
        _currency = State(initialValue: product.Currency ?? BmbCurrency.defaultCode)
    }

    var body: some View {
        BmbCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Price tips for this product").font(.headline)
                Text("Price when posted").font(.subheadline.bold())
                Text(product.Price.map { BmbMoney.display($0, currency: product.Currency) } ?? "—").font(.subheadline)
                if let captured = product.CapturedAt { Text(captured).font(.caption).foregroundStyle(BmbTheme.muted) }
                Text("Price I would accept").font(.subheadline.bold())
                Text(product.TargetPrice.map { BmbMoney.display($0, currency: product.Currency) } ?? "—").font(.subheadline)
                if isOwner && isOpen {
                    TextField("Edit target price; clear to remove", text: $target).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                    Button("Save target") { Task { await saveTarget() } }
                        .disabled(product.Currency == nil)
                }
                ForEach(offers) { offer in
                    Divider()
                    Text("\(offer.SiteName) · \(offer.CountryCode) · \(BmbMoney.display(offer.Price, currency: offer.Currency))").font(.subheadline.bold())
                    if offer.MeetsTarget {
                        Text("Meets target").font(.caption.bold()).foregroundStyle(.green)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("User reported")
                        Text("· \(offer.CreateTime)")
                        if offer.Status == "pending" { Text("· Awaiting review") }
                    }.font(.caption).foregroundStyle(BmbTheme.muted)
                    if let note = offer.Note { Text(note).font(.caption).fixedSize(horizontal: false, vertical: true) }
                    if let model = offer.Model { Text(model).font(.caption).fixedSize(horizontal: false, vertical: true) }
                    if offer.NeedsReconfirmation == true { Text(BmbEngagementCopy.text("Please reconfirm this price", "请重新确认价格")).font(.caption) }
                    if offer.Status == "approved" {
                        HStack {
                            ForEach(["expired", "mismatch"], id: \.self) { reason in
                                Button(BmbEngagementCopy.text(reason == "expired" ? "Expired" : "Different product", reason == "expired" ? "已失效" : "不是同款")) {
                                    Task {
                                        guard let token = session.token else { session.showLogin = true; return }
                                        do {
                                            let _: BmbAcknowledgement = try await session.api.call("/d/\(shareToken)/price-offers/\(offer.Id)/issues", method: "POST", body: ["Body": reason], token: token)
                                            message = BmbEngagementCopy.text("Feedback sent", "已提交反馈")
                                        } catch { message = error.localizedDescription }
                                    }
                                }
                            }
                        }
                    }
                    if let url = offer.Url, let link = URL(string: url) { Link("View product", destination: link) }
                }
                if isOpen {
                    Divider()
                    Text("Share a price you found").font(.subheadline.bold())
                    TextField("Website", text: $site).textFieldStyle(.roundedBorder)
                    TextField("Model (optional)", text: $model).textFieldStyle(.roundedBorder)
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
        .onChange(of: product.TargetPrice) { _, value in target = value.map { BmbMoney.number($0) } ?? "" }
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
                "ProductId": id, "SiteName": site, "Model": model, "CountryCode": country.uppercased(), "Price": amount,
                "Currency": currency, "Url": url, "Note": note
            ], token: token)
            site = ""; country = ""; price = ""; url = ""; note = ""
            message = String(localized: "Price submitted for review")
            await reload()
        } catch { message = error.localizedDescription }
    }
}
