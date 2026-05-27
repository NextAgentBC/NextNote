import Foundation

extension String {
    /// `nil` when the string is empty, otherwise `self`. Saves the
    /// `(x.isEmpty == false) ? x : nil` chains that pop up around metadata
    /// extraction (PDF / EPUB titles, optional author fields, etc.).
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
