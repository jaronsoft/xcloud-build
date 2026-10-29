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
                            Text(BmbEngagementCopy.text("Tap an option to vote. You can choose a reason first.", "点击选项即可投票；也可以先选填理由。"))
                                .font(.caption).foregroundStyle(BmbTheme.muted)
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                                ForEach(voteChoices, id: \.0) { key, label in
                                    Button { Task { await vote(key) } } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(label).fontWeight(.bold).fixedSize(horizontal: false, vertical: true)
                                            Text("\(decision.VoteCount == 0 ? 0 : Int(Double(decision.Votes[key] ?? 0) / Double(decision.VoteCount) * 100))% · \(decision.Votes[key] ?? 0) \(BmbEngagementCopy.text("votes", "票"))")
                                                .font(.caption)
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).padding(12)
                                        .background(key == "pass" || key == "b" ? Color.orange.opacity(0.16) : Color.green.opacity(0.16), in: RoundedRectangle(cornerRadius: 13))
                                    }
                                    .buttonStyle(.plain).disabled(decision.Status != "open")
                                }
                            }
                            DisclosureGroup(BmbEngagementCopy.text("Add a reason (optional)", "补充投票理由（可选）")) {
                                Text(BmbEngagementCopy.text("Choose a reason, then tap your vote above. Tap again to clear it.",
                                                            "选好理由后点击上方选项投票；再次点击理由可取消。"))
                                    .font(.caption).foregroundStyle(BmbTheme.muted)
                                ForEach(voteChoices, id: \.0) { key, label in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(label).font(.caption.bold()).foregroundStyle(BmbTheme.ink)
                                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                            ForEach(reasonChoices(for: key), id: \.self) { reason in
                                                let selected = voteReasons[key] == reason
                                                Button {
                                                    voteReasons[key] = selected ? nil : reason
                                                } label: {
                                                    HStack(spacing: 6) {
                                                        if selected { Image(systemName: "checkmark.circle.fill") }
                                                        Text(BmbEngagementCopy.reason(reason))
                                                            .multilineTextAlignment(.leading)
                                                        if let count = decision.VoteReasons?[key]?[reason], count > 0 {
                                                            Spacer(minLength: 2)
                                                            Text("\(count)").foregroundStyle(BmbTheme.muted)
                                                        }
                                                    }
                                                    .font(.caption)
                                                    .foregroundStyle(BmbTheme.ink)
                                                    .padding(.horizontal, 10)
                                                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                                                    .background(selected ? BmbTheme.lime : BmbTheme.paper,
                                                                in: RoundedRectangle(cornerRadius: 10))
                                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                                                }
                                                .buttonStyle(.plain)
                                                .disabled(decision.Status != "open")
                                                .accessibilityAddTraits(selected ? .isSelected : [])
                                            }
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                            }
                            Text("\(decision.VoteCount) \(BmbEngagementCopy.text("votes", "票"))").font(.caption).foregroundStyle(BmbTheme.muted)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    ForEach(Array(decision.Products.enumerated()), id: \.offset) { _, product in
                        PriceOfferSection(shareToken: shareToken, product: product,
                            offers: decision.PriceOffers.filter { $0.ProductId == product.Id },
                            isOwner: decision.IsOwner, isOpen: decision.Status == "open", reload: load)
                        PromoLinkSection(shareToken: shareToken, product: product,
                            links: (decision.PromoLinks ?? []).filter { $0.ProductId == product.Id },
                            isOpen: decision.Status == "open", reload: load)
                    }
                    BmbDecisionTools(item: decision, reload: load)
                    if let choice = decision.FinalChoice {
                        Label(BmbEngagementCopy.text("Final choice: \(BmbEngagementCopy.finalChoice(choice))", "最终选择：\(BmbEngagementCopy.finalChoice(choice))"), systemImage: "checkmark.seal")
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
                                Text(BmbEngagementCopy.text("Sign in to share your opinion.", "登录后可以发表您的看法。"))
                                    .font(.caption).foregroundStyle(BmbTheme.muted)
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
        .navigationTitle("")
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
    private func reasonChoices(for key: String) -> [String] {
        key == "buy" ? ["useful", "value", "quality", "frequent", "long_term"]
            : key == "pass" ? ["expensive", "duplicate", "wait", "uncertain", "extra_cost"]
            : ["value", "fit", "quality", "comfort", "design"]
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
            comment = ""; suggestedURL = ""; message = BmbLanguage.localized("Your comment is awaiting review.")
            await load()
        } catch { message = error.localizedDescription }
    }
    private func report() async {
        guard let token = session.token else { session.showLogin = true; return }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/d/\(shareToken)/reports", method: "POST", body: ["Reason": reportReason], token: token)
            message = BmbLanguage.localized("Report sent")
        } catch { message = error.localizedDescription }
    }
}

private struct PromoLinkSection: View {
    let shareToken: String
    let product: BmbProduct
    let links: [BmbPromoLink]
    let isOpen: Bool
    let reload: () async -> Void
    @EnvironmentObject private var session: BmbSession
    @State private var showForm = false
    @State private var url = ""
    @State private var note = ""
    @State private var message: String?

    var body: some View {
        BmbCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(BmbEngagementCopy.text("Creator offers", "博主优惠链接")).font(.headline)
                Text(BmbEngagementCopy.text("Have a relevant discount link? Share it with someone deciding.", "有适用的优惠链接？分享给正在考虑购买的人。"))
                    .font(.caption).foregroundStyle(BmbTheme.muted)
                ForEach(links) { link in
                    Divider()
                    Text(BmbEngagementCopy.text("Promotional link", "推广链接")).font(.caption.bold()).foregroundStyle(.green)
                    Text(link.Note).font(.subheadline)
                    if let destination = URL(string: link.Url) { Link(BmbEngagementCopy.text("View link", "查看链接"), destination: destination) }
                    if link.Status == "pending" { Text(BmbEngagementCopy.text("Awaiting review", "待审核")).font(.caption) }
                    if link.Status == "approved" {
                        HStack {
                            Button(BmbEngagementCopy.text("Expired", "链接失效")) { Task { await report(link, reason: "expired") } }
                            Button(BmbEngagementCopy.text("Not relevant", "内容不相关")) { Task { await report(link, reason: "irrelevant") } }
                        }.font(.caption)
                    }
                }
                if isOpen {
                    BmbActionRow(title: BmbEngagementCopy.text("Share my offer link", "推荐我的优惠链接"),
                                 systemImage: "link", trailingSymbol: showForm ? "chevron.up" : "chevron.down",
                                 emphasized: true) { showForm.toggle() }
                    if showForm {
                        TextField("https://…", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
                        TextField(BmbEngagementCopy.text("Offer and conditions", "优惠内容与条件"), text: $note, axis: .vertical)
                            .lineLimit(2...4).textFieldStyle(.roundedBorder)
                        Button(session.isLoggedIn ? BmbEngagementCopy.text("Send for review", "提交审核") : BmbEngagementCopy.text("Sign in to share", "登录后推荐")) {
                            Task { await submit() }
                        }.disabled(!url.hasPrefix("https://") || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.orange) }
            }
        }
    }

    private func submit() async {
        guard let token = session.token else { session.showLogin = true; return }
        guard let productId = product.Id else { return }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/d/\(shareToken)/promo-links", method: "POST",
                body: ["ProductId": productId, "Url": url, "Note": note], token: token)
            url = ""; note = ""; showForm = false
            message = BmbEngagementCopy.text("Sent for review", "已提交审核")
            await reload()
        } catch { message = error.localizedDescription }
    }

    private func report(_ link: BmbPromoLink, reason: String) async {
        guard let token = session.token else { session.showLogin = true; return }
        do {
            let _: BmbAcknowledgement = try await session.api.call("/d/\(shareToken)/promo-links/\(link.Id)/issues", method: "POST",
                body: ["Body": reason], token: token)
            message = BmbEngagementCopy.text("Feedback sent", "已反馈")
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
    @State private var showForm = false
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
                if isOpen {
                    BmbActionRow(title: BmbEngagementCopy.text("I found a better price", "我发现了更好的价格"),
                                 systemImage: "tag", trailingSymbol: showForm ? "chevron.up" : "chevron.down",
                                 emphasized: true) { showForm.toggle() }
                }
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
                if isOpen { Divider() }
                if isOpen && showForm {
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
            message = BmbLanguage.localized("Target price updated")
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
            message = BmbLanguage.localized("Price submitted for review")
            await reload()
        } catch { message = error.localizedDescription }
    }
}
