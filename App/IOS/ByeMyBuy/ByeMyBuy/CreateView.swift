import SwiftUI
import PhotosUI
import UIKit

enum BmbCurrency {
    static let codes = ["USD", "CNY", "EUR", "GBP", "JPY", "CAD", "AUD", "HKD", "SGD", "KRW", "TWD", "INR"]
    static var defaultCode: String {
        let local = Locale.current.currency?.identifier.uppercased() ?? "USD"
        return codes.contains(local) ? local : "USD"
    }
}

struct ProductDraft: Identifiable {
    let id = UUID()
    var title = ""
    var model = ""
    var url = ""
    var imageURL = ""
    var imageData: Data?
    var photoItem: PhotosPickerItem?
    var price = ""
    var currency = BmbCurrency.defaultCode

    var product: BmbProduct {
        BmbProduct(Title: title, Model: model.isEmpty ? nil : model, Url: url.isEmpty ? nil : url, ImageUrl: imageURL.isEmpty ? nil : imageURL,
                   Price: Double(price), Currency: currency, Source: "user")
    }
}

struct CreateView: View {
    @EnvironmentObject private var session: BmbSession
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "buy_pass"
    @State private var visibility = "private"
    @State private var question = ""
    @State private var products = [ProductDraft(), ProductDraft()]
    @State private var isBusy = false
    @State private var error: String?
    @State private var publishedToken: BmbTokenItem?

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
                            TextField("Model (optional)", text: $products[index].model).textFieldStyle(.roundedBorder)
                            HStack {
                                TextField("Price", text: $products[index].price).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                                Picker("Currency", selection: $products[index].currency) {
                                    ForEach(BmbCurrency.codes, id: \.self) { code in Text(code).tag(code) }
                                }.frame(width: 110)
                            }
                            PhotosPicker(selection: $products[index].photoItem, matching: .images) {
                                Label("Choose a photo", systemImage: "photo.on.rectangle").font(.subheadline.bold())
                            }
                            .onChange(of: products[index].photoItem) { _, selected in
                                Task {
                                    guard let bytes = try? await selected?.loadTransferable(type: Data.self),
                                          let image = UIImage(data: bytes),
                                          let jpeg = image.jpegData(compressionQuality: 0.85) else { return }
                                    if jpeg.count > 5 * 1024 * 1024 {
                                        error = String(localized: "Choose a photo under 5 MB.")
                                    } else {
                                        products[index].imageData = jpeg
                                        error = nil
                                    }
                                }
                            }
                            if let data = products[index].imageData, let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFit().frame(height: 180)
                            }
                            TextField("Image URL (optional)", text: $products[index].imageURL).textInputAutocapitalization(.never).keyboardType(.URL).textFieldStyle(.roundedBorder)
                            DisclosureGroup("Product URL (optional)") {
                                TextField("https://…", text: $products[index].url).textInputAutocapitalization(.never).keyboardType(.URL).textFieldStyle(.roundedBorder)
                                Button(isBusy ? "Reading…" : "Get details") { Task { await resolve(index) } }
                                    .disabled(products[index].url.isEmpty || isBusy)
                            }
                        }
                    }
                }
                BmbCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What should your friends know?").font(.headline)
                        TextField("I love this, but I already own something similar…", text: $question, axis: .vertical)
                            .lineLimit(3...6).textFieldStyle(.roundedBorder)
                    }
                }
                BmbCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Who can see this?").font(.headline)
                        Picker("Visibility", selection: $visibility) {
                            Text("Link only").tag("private")
                            Text("Explore").tag("public")
                        }.pickerStyle(.segmented)
                        Text(visibility == "public" ? "Anyone can find and vote on this decision." : "Only people with the link can open this decision.")
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
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } } }
        .sheet(item: $publishedToken) { token in
            NavigationStack { DecisionView(shareToken: token.value) }.environmentObject(session)
        }
    }

    private func resolve(_ index: Int) async {
        isBusy = true; defer { isBusy = false }
        do {
            let product = try await session.api.resolve(products[index].url)
            products[index].title = product.Title
            products[index].model = product.Model ?? ""
            products[index].url = product.Url ?? ""
            products[index].imageURL = product.ImageUrl ?? ""
            products[index].price = product.Price.map { String($0) } ?? ""
            products[index].currency = product.Currency ?? "USD"
            error = nil
        } catch { self.error = String(localized: "We couldn’t read that page. Fill in the details yourself.") }
    }

    private func publish() async {
        guard products.prefix(mode == "pick_one" ? 2 : 1).allSatisfy({ !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            error = String(localized: "Enter a product name first.")
            return
        }
        guard let token = session.token else { session.showLogin = true; return }
        isBusy = true; defer { isBusy = false }
        do {
            var fields: [[String: Any]] = []
            for item in products.prefix(mode == "pick_one" ? 2 : 1) {
                var value: [String: Any] = ["Title": item.title, "Currency": item.currency, "Source": "user"]
                if !item.model.isEmpty { value["Model"] = item.model }
                if !item.url.isEmpty { value["Url"] = item.url }
                if let data = item.imageData { value["ImageUrl"] = try await session.api.uploadProductImage(data, token: token) }
                else if !item.imageURL.isEmpty { value["ImageUrl"] = item.imageURL }
                if let price = Double(item.price) { value["Price"] = price }
                fields.append(value)
            }
            let result: BmbDecision = try await session.api.call("/decisions", method: "POST",
                body: ["Mode": mode, "Visibility": visibility, "Question": question, "Products": fields], token: token)
            publishedToken = BmbTokenItem(value: result.ShareToken)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
