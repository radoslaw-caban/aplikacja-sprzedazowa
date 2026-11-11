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
    public var hasContact: Bool {
        !phone.isEmpty || !email.isEmpty || !address.isEmpty
    }

    /// Postęp zaliczki 0…1.
    public var depositProgress: Double {
        guard price > 0 else { return 0 }
        return min(1, max(0, deposit / price))
    }
}
