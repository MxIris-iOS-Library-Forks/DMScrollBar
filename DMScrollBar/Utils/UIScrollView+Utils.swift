import UIKit

private enum AssociatedKeys {
    static var scrollIndicatorStyle = "scrollIndicatorStyle"
    static var verticalScrollBar = "verticalScrollBar"
    static var horizontalScrollBar = "horizontalScrollBar"
}

public extension UIScrollView {
    
    var horizontalScrollBar: DMScrollBar? {
        get {
            withUnsafePointer(to: &AssociatedKeys.horizontalScrollBar) {
                objc_getAssociatedObject(self, $0) as? DMScrollBar
            }
        } set {
            withUnsafePointer(to: &AssociatedKeys.horizontalScrollBar) {
                objc_setAssociatedObject(self, $0, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }
    
    var verticalScrollBar: DMScrollBar? {
        get {
            withUnsafePointer(to: &AssociatedKeys.verticalScrollBar) {
                objc_getAssociatedObject(self, $0) as? DMScrollBar
            }
        } set {
            withUnsafePointer(to: &AssociatedKeys.verticalScrollBar) {
                objc_setAssociatedObject(self, $0, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }

    func configureScrollBar(with configuration: DMScrollBar.Configuration = .default, delegate: DMScrollBarDelegate? = nil) {
        switch configuration.direction {
        case .horizontal:
            horizontalScrollBar?.removeFromSuperview()
            let scrollBar = DMScrollBar(scrollView: self, delegate: delegate, configuration: configuration)
            self.horizontalScrollBar = scrollBar
        case .vertical:
            verticalScrollBar?.removeFromSuperview()
            let scrollBar = DMScrollBar(scrollView: self, delegate: delegate, configuration: configuration)
            self.verticalScrollBar = scrollBar
        }
    }
}

//private enum AssociatedKeys {
//    static var scrollIndicatorStyle = "scrollIndicatorStyle"
//    static var scrollBar = "scrollBar"
//}
//
//public extension UIScrollView {
//    var scrollBar: DMScrollBar? {
//        get {
//            withUnsafePointer(to: &AssociatedKeys.scrollBar) {
//                objc_getAssociatedObject(self, $0) as? DMScrollBar
//            }
//        } set {
//            withUnsafePointer(to: &AssociatedKeys.scrollBar) {
//                objc_setAssociatedObject(self, $0, newValue, .OBJC_ASSOCIATION_ASSIGN)
//            }
//        }
//    }
//
//    func configureScrollBar(with configuration: DMScrollBar.Configuration = .default, delegate: DMScrollBarDelegate? = nil) {
//        scrollBar?.removeFromSuperview()
//        let scrollBar = DMScrollBar(scrollView: self, delegate: delegate, configuration: configuration)
//        self.scrollBar = scrollBar
//    }
//}
