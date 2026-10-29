import SwiftUI
import PhotosUI
import UIKit

enum BmbCurrency {
    static let codes = ["USD", "CNY", "EUR", "GBP", "JPY", "CAD", "AUD", "HKD", "SGD", "KRW", "TWD", "INR"]
    static let emoji = ["USD": "🇺🇸", "CNY": "🇨🇳", "EUR": "🇪🇺", "GBP": "🇬🇧", "JPY": "🇯🇵", "CAD": "🇨🇦", "AUD": "🇦🇺", "HKD": "🇭🇰", "SGD": "🇸🇬", "KRW": "🇰🇷", "TWD": "🇹🇼", "INR": "🇮🇳"]
    static func label(_ code: String) -> String { "\(emoji[code] ?? "💱") \(code)" }
    static var defaultCode: String {
        let local = Locale.current.currency?.identifier.uppercased() ?? "USD"
        return codes.contains(local) ? local : "USD"
    }
}

struct ProductDraft: Identifiable, Codable {
    enum CodingKeys: String, CodingKey { case title, model, tagsText, url, imageURL, imageData, price, currency, targetPrice, discountPercent }
    let id = UUID()
    var title = ""
    var model = ""
    var tagsText = ""
    var url = ""
    var imageURL = ""
    var imageData: Data?
    var photoItem: PhotosPickerItem?
    var price = ""
    var currency = BmbCurrency.defaultCode
    var targetPrice = ""
    var discountPercent: Double?

    var product: BmbProduct {
        BmbProduct(Title: title, Model: model.isEmpty ? nil : model, Url: url.isEmpty ? nil : url, ImageUrl: imageURL.isEmpty ? nil : imageURL,
                   Price: Double(price), Currency: currency, Source: "user")
    }
}

struct CreateView: View {
    @EnvironmentObject private var session: BmbSession
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "buy_pass"
    @State private var visibility = "public"
    @State private var language = BmbLanguage.code
    @State private var question = ""
    @State private var hesitation = ""
    @State private var products = [ProductDraft(), ProductDraft()]
    @State private var isBusy = false
    @State private var photoBusy = Set<Int>()
    @State private var error: String?
    @State private var publishedDecision: BmbDecision?

    private struct StoredDraft: Codable {
        var mode: String
        var visibility: String
        var language: String?
        var question: String
        var hesitation: String
        var products: [ProductDraft]
    }
    private static var draftURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("byemybuy-create-draft.json")
    }
    private var draftData: Data? {
        try? JSONEncoder().encode(StoredDraft(mode: mode, visibility: visibility, language: language, question: question, hesitation: hesitation, products: products))
    }
    init() {
        if let data = try? Data(contentsOf: Self.draftURL), let draft = try? JSONDecoder().decode(StoredDraft.self, from: data), draft.products.count == 2 {
            _mode = State(initialValue: draft.mode); _visibility = State(initialValue: draft.visibility)
            _language = State(initialValue: draft.language == "zh" ? "zh" : "en")
            _question = State(initialValue: draft.question); _hesitation = State(initialValue: draft.hesitation)
            _products = State(initialValue: draft.products)
        }
    }
    private func saveDraft() {
        guard publishedDecision == nil, let data = draftData else { return }
        try? FileManager.default.createDirectory(at: Self.draftURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.draftURL, options: [.atomic, .completeFileProtection])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("What are you thinking of buying?").font(.system(size: 34, weight: .black, design: .rounded)).tracking(-1.8)
                Text("Start with the product name. A link is optional.").foregroundStyle(BmbTheme.muted)
                Picker("Decision type", selection: $mode) {
                    Text("Buy or pass").tag("buy_pass")
                    Text("Pick one").tag("pick_one")
                }.pickerStyle(.segmented)
                ForEach(0..<(mode == "pick_one" ? 2 : 1), id: \.self) { index in
                    BmbCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(mode == "pick_one" ? "Option \(index == 0 ? "A" : "B")" : "Product card").font(.headline)
                            TextField("Product name", text: $products[index].title).textFieldStyle(.roundedBorder)
                            DisclosureGroup(BmbEngagementCopy.text("More product details (optional)", "补充商品信息（可选）")) {
                            TextField("Model (optional)", text: $products[index].model).textFieldStyle(.roundedBorder)
                            TextField("Tags (optional, comma separated)", text: $products[index].tagsText).textFieldStyle(.roundedBorder)
                            HStack {
                                TextField("Price", text: $products[index].price).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                                    .onChange(of: products[index].price) { _, _ in
                                        if let percentage = products[index].discountPercent {
                                            setDiscount(at: index, percentage: percentage)
                                        }
                                    }
                                Picker("Currency", selection: $products[index].currency) {
                                    ForEach(BmbCurrency.codes, id: \.self) { code in Text(BmbCurrency.label(code)).tag(code) }
                                }.frame(width: 110)
                            }
                            HStack {
                                TextField("Price I would accept (optional)", text: Binding(
                                    get: { products[index].targetPrice },
                                    set: { value in
                                        products[index].targetPrice = moneyInput(value)
                                        products[index].discountPercent = nil
                                    }
                                )).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                                VStack(spacing: 0) {
                                    Slider(value: Binding(
                                        get: { products[index].discountPercent ?? 0 },
                                        set: { setDiscount(at: index, percentage: $0) }
                                    ), in: 0...100, step: 10)
                                    .accessibilityLabel(Text("Discount"))
                                    .accessibilityValue("\(Int(products[index].discountPercent ?? 0))%")
                                    Text(products[index].discountPercent.map { "−\(Int($0))%" } ?? BmbLanguage.localized("10% steps"))
                                        .font(.caption2).foregroundStyle(BmbTheme.muted)
                                }
                                .frame(width: 110)
                                .disabled((Decimal(string: products[index].price.replacingOccurrences(of: ",", with: ".")) ?? 0) <= 0)
                            }
                            }
                            let previewData = products[index].imageData
                            let hasPhoto = previewData != nil || !products[index].imageURL.isEmpty
                            PhotosPicker(selection: $products[index].photoItem, matching: .images) {
                                HStack(spacing: 16) {
                                    if let data = previewData, let image = UIImage(data: data) {
                                        Image(uiImage: image).resizable().scaledToFill()
                                            .frame(width: 82, height: 82).clipShape(RoundedRectangle(cornerRadius: 12))
                                    } else {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.system(size: 34)).foregroundStyle(BmbTheme.muted)
                                            .frame(width: 82, height: 82)
                                    }
                                    VStack(alignment: .leading, spacing: 7) {
                                        if !hasPhoto {
                                            Text("Choose a photo").font(.headline).foregroundStyle(BmbTheme.ink)
                                            Text("Tap anywhere to add a photo").font(.caption).foregroundStyle(BmbTheme.muted)
                                        } else {
                                            Text("Replace photo").font(.headline).foregroundStyle(BmbTheme.ink)
                                            Text("Tap anywhere to replace the photo").font(.caption).foregroundStyle(BmbTheme.muted)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
                                .padding(16)
                                .background(BmbTheme.hero.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(BmbTheme.muted.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
                            }
                            .buttonStyle(.plain)
                            .disabled(photoBusy.contains(index) || isBusy)
                            .onChange(of: products[index].photoItem) { _, selected in
                                Task {
                                    guard selected != nil, !photoBusy.contains(index) else { return }
                                    photoBusy.insert(index)
                                    defer { photoBusy.remove(index) }
                                    guard let bytes = try? await selected?.loadTransferable(type: Data.self),
                                          let image = UIImage(data: bytes),
                                          let jpeg = image.jpegData(compressionQuality: 0.85) else {
                                        products[index].photoItem = nil
                                        return
                                    }
                                    if jpeg.count > 5 * 1024 * 1024 {
                                        error = BmbLanguage.localized("Choose a photo under 5 MB.")
                                        products[index].photoItem = nil
                                    } else {
                                        do { try await discardRemotePhoto(at: index) }
                                        catch { self.error = error.localizedDescription; products[index].photoItem = nil; return }
                                        products[index].imageData = jpeg
                                        error = nil
                                    }
                                }
                            }
                            if products[index].imageData != nil || !products[index].imageURL.isEmpty {
                                Button("Remove photo", role: .destructive) { Task { await removePhoto(at: index) } }
                                    .disabled(photoBusy.contains(index) || isBusy)
                            }
                            if products[index].imageData == nil {
                                TextField("Image URL (optional)", text: $products[index].imageURL).textInputAutocapitalization(.never).keyboardType(.URL).textFieldStyle(.roundedBorder)
                                    .disabled(photoBusy.contains(index) || isBusy)
                            }
                            DisclosureGroup("Product URL (optional)") {
                                TextField("https://…", text: $products[index].url).textInputAutocapitalization(.never).keyboardType(.URL).textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }
                BmbCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What should others know?").font(.headline)
                        Picker(BmbEngagementCopy.text("What gives you pause?", "你在犹豫什么？"), selection: $hesitation) {
                            Text("—").tag("")
                            Text(BmbEngagementCopy.text("Might not use it", "担心用不上")).tag("need")
                            Text(BmbEngagementCopy.text("Price is high", "价格偏高")).tag("price")
                            Text(BmbEngagementCopy.text("Have something similar", "已有类似商品")).tag("duplicate")
                            Text(BmbEngagementCopy.text("Unsure which one", "不知道选哪个")).tag("choice")
                        }
                        VStack(spacing: 8) {
                            questionPreset(BmbLanguage.localized("Do I need this?"))
                            questionPreset(BmbEngagementCopy.text("Should I buy now or wait?", "现在买还是等等？"))
                            if mode == "pick_one" {
                                questionPreset(BmbLanguage.localized("Which one suits me?"))
                            } else {
                                questionPreset(BmbLanguage.localized("I already own something similar."))
                            }
                        }
                        TextField("I love this, but I already own something similar…", text: $question, axis: .vertical)
                            .lineLimit(3...6).textFieldStyle(.roundedBorder)
                    }
                }
                BmbCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Who can see this?").font(.headline)
                        Picker(BmbEngagementCopy.text("Content language", "内容语言"), selection: $language) {
                            Text("简体中文").tag("zh")
                            Text("English").tag("en")
                        }
                        VStack(spacing: 8) {
                            visibilityChoice("private", title: "Link only")
                            visibilityChoice("public", title: "Submit to Explore (after review)")
                        }
                        Text(LocalizedStringKey(visibility == "public" ? "Explore can find this after review. Your share link works now." : "Only people with the link can open this decision."))
                            .font(.caption).foregroundStyle(BmbTheme.muted)
                    }
                }
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                BmbPrimaryButton(title: "Publish and share") { Task { await publish() } }
                    .disabled(isBusy)
            }.padding(20)
        }
        .background(BmbTheme.paper)
        .navigationTitle("New decision")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: draftData) {
            do { try await Task.sleep(for: .milliseconds(400)); saveDraft() } catch { }
        }
        .onDisappear { saveDraft() }
        .task { await session.api.track("create_started", token: session.token) }
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        .task {
            if session.profile == nil { await session.loadProfile() }
            guard let code = session.profile?.DefaultCurrency, BmbCurrency.codes.contains(code) else { return }
            for index in products.indices where products[index].title.isEmpty && products[index].price.isEmpty {
                products[index].currency = code
            }
        }
        .sheet(item: $publishedDecision, onDismiss: { dismiss() }) { decision in
            NavigationStack { BmbDecisionShareView(decision: decision, isPublished: true) }
                .environmentObject(session)
        }
    }

    private func questionPreset(_ value: String) -> some View {
        let selected = question == value
        return Button { question = value } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "text.bubble")
                    .foregroundStyle(selected ? BmbTheme.ink : BmbTheme.muted)
                Text(value).font(.subheadline.weight(.medium)).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 14)
            .foregroundStyle(BmbTheme.ink)
            .background(selected ? BmbTheme.hero : BmbTheme.paper, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(selected ? BmbTheme.lime : BmbTheme.muted.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func visibilityChoice(_ value: String, title: LocalizedStringKey) -> some View {
        let selected = visibility == value
        return Button { visibility = value } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? BmbTheme.ink : BmbTheme.muted)
                Text(title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .padding(.horizontal, 14)
            .foregroundStyle(BmbTheme.ink)
            .background(selected ? BmbTheme.hero : BmbTheme.paper, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(selected ? BmbTheme.lime : BmbTheme.muted.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func moneyInput(_ value: String) -> String {
        var result = ""
        var hasDecimalPoint = false
        var fractionDigits = 0
        for character in value.replacingOccurrences(of: ",", with: ".") {
            if character == "." && !hasDecimalPoint {
                result += result.isEmpty ? "0." : "."
                hasDecimalPoint = true
            } else if let digit = character.wholeNumberValue, (0...9).contains(digit),
                      !hasDecimalPoint || fractionDigits < 2 {
                result += String(digit)
                if hasDecimalPoint { fractionDigits += 1 }
            }
        }
        return result
    }

    private func setDiscount(at index: Int, percentage: Double) {
        products[index].discountPercent = percentage
        guard let price = Decimal(string: products[index].price.replacingOccurrences(of: ",", with: ".")), price > 0 else {
            products[index].targetPrice = ""
            return
        }
        var amount = price * Decimal(100 - Int(percentage)) / Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &amount, 2, .plain)
        products[index].targetPrice = NSDecimalNumber(decimal: rounded).stringValue
    }

    private func discardRemotePhoto(at index: Int) async throws {
        let imageURL = products[index].imageURL
        guard !imageURL.isEmpty else { return }
        if imageURL.hasPrefix("https://") {
            guard let token = session.token else { throw BmbError(message: BmbLanguage.localized("Sign in to remove this photo.")) }
            try await session.api.deleteProductImage(imageURL, token: token)
        }
        products[index].imageURL = ""
    }

    private func removePhoto(at index: Int) async {
        guard !photoBusy.contains(index), !isBusy else { return }
        photoBusy.insert(index)
        defer { photoBusy.remove(index) }
        do {
            try await discardRemotePhoto(at: index)
            products[index].imageData = nil
            products[index].photoItem = nil
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func publish() async {
        guard photoBusy.isEmpty else { error = BmbLanguage.localized("Please wait for the photo to finish processing."); return }
        guard products.prefix(mode == "pick_one" ? 2 : 1).allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            error = BmbLanguage.localized("Enter a product name first.")
            return
        }
        guard let token = session.token else { session.showLogin = true; return }
        isBusy = true; defer { isBusy = false }
        var uploadedURLs: [String] = []
        do {
            var fields: [[String: Any]] = []
            for item in products.prefix(mode == "pick_one" ? 2 : 1) {
                var value: [String: Any] = ["Title": item.title, "Currency": item.currency, "Source": "user"]
                if !item.model.isEmpty { value["Model"] = item.model }
                let tags = item.tagsText.split(whereSeparator: { $0 == "," || $0 == "，" }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                if !tags.isEmpty { value["Tags"] = tags }
                if !item.url.isEmpty { value["Url"] = item.url }
                if let data = item.imageData {
                    let imageURL = try await session.api.uploadProductImage(data, token: token)
                    uploadedURLs.append(imageURL)
                    value["ImageUrl"] = imageURL
                }
                else if !item.imageURL.isEmpty { value["ImageUrl"] = item.imageURL }
                if let price = Double(item.price) { value["Price"] = price }
                if let target = Double(item.targetPrice) {
                    value["TargetPrice"] = target
                    value["TargetCurrency"] = item.currency
                }
                fields.append(value)
            }
            let result: BmbDecision = try await session.api.call("/decisions", method: "POST",
                body: ["Mode": mode, "Visibility": visibility, "Language": language, "Question": question, "Hesitation": hesitation, "Products": fields], token: token)
            try? FileManager.default.removeItem(at: Self.draftURL)
            publishedDecision = result
            error = nil
        } catch {
            for imageURL in uploadedURLs { try? await session.api.deleteProductImage(imageURL, token: token) }
            self.error = error.localizedDescription
        }
    }
}
