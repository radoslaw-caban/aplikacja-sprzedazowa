import Foundation

/// Szczegóły zamówienia — ekran startowy aplikacji (zielony na diagramie
/// przepływu). Wszystko, co handlowiec zapisuje przy pierwszej rozmowie
/// z klientem, w jednym miejscu i w jednym pliku projektu.
public struct ProjectOrder: Codable, Sendable, Equatable {

    public var clientLastName: String
    public var clientFirstName: String
    public var address: String
    public var phone: String
    public var email: String
    /// Wartość oferty (zł).
    public var price: Double
    /// Zaliczka wpłacona przez klienta (zł).
    public var deposit: Double
    /// Co klient chce zmienić względem pierwszej wersji.
    public var changeReason: String
    /// Konwersacja z klientem: notatki ze spotkania, ustalenia, terminy.
    public var notes: String
    /// Data dostawy (z tabeli zamówień). `nil` = jeszcze nie ustalona.
    public var deliveryDate: Date?
    /// Rabat klienta w procentach (0–100). Pomniejsza cenę końcową.
    public var discountPercent: Double?
    /// Data podpisania umowy (nil = nie podpisana).
    public var contractSignedAt: Date?
    /// Nazwa pliku z podpisem (Documents/umowy/…png).
    public var contractSignatureFile: String?
    /// Status zamówienia w formie tekstowej („Do dostarczenia", „W realizacji").
    public var status: String?
    public var updatedAt: Date

    public init(
        clientLastName: String = "",
        clientFirstName: String = "",
        address: String = "",
        phone: String = "",
        email: String = "",
        price: Double = 0,
        deposit: Double = 0,
        changeReason: String = "",
        notes: String = "",
        deliveryDate: Date? = nil,
        discountPercent: Double? = nil,
        contractSignedAt: Date? = nil,
        contractSignatureFile: String? = nil,
        status: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.clientLastName = clientLastName
        self.clientFirstName = clientFirstName
        self.address = address
        self.phone = phone
        self.email = email
        self.price = price
        self.deposit = deposit
        self.changeReason = changeReason
        self.notes = notes
        self.deliveryDate = deliveryDate
        self.discountPercent = discountPercent
        self.contractSignedAt = contractSignedAt
        self.contractSignatureFile = contractSignatureFile
        self.status = status
        self.updatedAt = updatedAt
    }

    /// „Kowalski Jan" — do nagłówka i listy projektów.
    public var clientName: String {
        let full = "\(clientLastName) \(clientFirstName)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? "Klient bez nazwiska" : full
    }

    /// Do zapłaty po zaliczce (zł).
    public var remaining: Double { max(0, price - deposit) }

    /// Czy zamówienie ma już dane kontaktowe (do statusu w UI).
    /// Rabat ograniczony do 0–100 %.
    public var effectiveDiscount: Double {
        min(100, max(0, discountPercent ?? 0))
    }

    public var discountAmount: Double {
        price * effectiveDiscount / 100
    }

    /// Cena po rabacie — to pokazuje karta rozliczeniowa.
    public var finalPrice: Double {
        max(0, price - discountAmount)
    }

    public var isContractSigned: Bool { contractSignedAt != nil }

    public var hasContact: Bool {
        !phone.isEmpty || !email.isEmpty || !address.isEmpty
    }

    /// Postęp zaliczki 0…1.
    public var depositProgress: Double {
        guard price > 0 else { return 0 }
        return min(1, max(0, deposit / price))
    }
}
