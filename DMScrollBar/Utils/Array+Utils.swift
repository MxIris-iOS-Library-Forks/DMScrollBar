import Foundation

extension Array {
    subscript(safe index: Int) -> Element? {
        set {
            if index < count, index >= 0, let newValue = newValue {
                self[index] = newValue
            }
        }
        get {
            (index < count && index >= 0) ? self[index] : nil
        }
    }
    
    var lastlast: Element? {
        self[count - 2]
    }
}
