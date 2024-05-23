import UIKit
import Combine

public class DMScrollBar: UIView {
    // MARK: - Public

    public let configuration: Configuration

    // MARK: - Properties

    private weak var scrollView: UIScrollView?
    private weak var delegate: DMScrollBarDelegate?
    private let scrollIndicator = ScrollBarIndicator()
    private let infoView = ScrollBarInfoView()

    private var scrollIndicatorTopConstraint: NSLayoutConstraint?
    private var scrollIndicatorLeadingConstraint: NSLayoutConstraint?

    private var scrollIndicatorTrailingConstraint: NSLayoutConstraint?
    private var scrollIndicatorBottomConstraint: NSLayoutConstraint?

    private var scrollIndicatorWidthConstraint: NSLayoutConstraint?
    private var scrollIndicatorHeightConstraint: NSLayoutConstraint?

    private var infoViewToScrollIndicatorConstraint: NSLayoutConstraint?

    private var cancellables = Set<AnyCancellable>()
    private var hideTimer: Timer?
    private var panGestureRecognizer: UIPanGestureRecognizer?
    private var longPressGestureRecognizer: UILongPressGestureRecognizer?
    private var decelerateAnimation: TimerAnimation?

    private var scrollIndicatorOffsetOnGestureStart: CGFloat?
    private var wasInteractionStartedWithLongPress = false

    private var scrollViewLayoutGuide: UILayoutGuide? {
        configuration.indicator.insetsFollowsSafeArea ?
            scrollView?.safeAreaLayoutGuide :
            scrollView?.frameLayoutGuide
    }

    // MARK: - Initial setup

    public init(
        scrollView: UIScrollView,
        delegate: DMScrollBarDelegate? = nil,
        configuration: Configuration = .default
    ) {
        self.scrollView = scrollView
        self.configuration = configuration
        self.delegate = delegate
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupScrollView()
        setupConstraints()
        setupScrollIndicator()
        setupAdditionalInfoView()
        setupInitialAlpha()
        observeScrollViewProperties()
        addGestureRecognizers()
    }

    public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let result = super.hitTest(point, with: event)
        guard result == self else { return result }
        switch configuration.direction {
        case .horizontal:
            return scrollIndicator.frame.minX ... scrollIndicator.frame.maxX ~= point.x ? self : nil
        case .vertical:
            return scrollIndicator.frame.minY ... scrollIndicator.frame.maxY ~= point.y ? self : nil
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    private func setupConstraints() {
        guard let scrollView, let scrollViewLayoutGuide else { return }
        scrollView.addSubview(self)
        let minimumWidth: CGFloat = 20
        switch configuration.direction {
        case .horizontal:
            trailingAnchor.constraint(equalTo: scrollViewLayoutGuide.trailingAnchor).isActive = true
            leftAnchor.constraint(equalTo: scrollViewLayoutGuide.leftAnchor).isActive = true
            bottomAnchor.constraint(equalTo: scrollViewLayoutGuide.bottomAnchor).isActive = true
            heightAnchor.constraint(equalToConstant: max(minimumWidth, configuration.indicator.normalState.size.height)).isActive = true
        case .vertical:
            bottomAnchor.constraint(equalTo: scrollViewLayoutGuide.bottomAnchor).isActive = true
            topAnchor.constraint(equalTo: scrollViewLayoutGuide.topAnchor).isActive = true
            trailingAnchor.constraint(equalTo: scrollViewLayoutGuide.trailingAnchor).isActive = true
            widthAnchor.constraint(equalToConstant: max(minimumWidth, configuration.indicator.normalState.size.width)).isActive = true
        }
    }

    private func setupInitialAlpha() {
        alpha = configuration.isAlwaysVisible ? 1 : 0
    }

    private func setupScrollView() {
        switch configuration.direction {
        case .horizontal:
            scrollView?.showsHorizontalScrollIndicator = false
        case .vertical:
            scrollView?.showsVerticalScrollIndicator = false
        }
        scrollView?.layoutIfNeeded()
    }

    private func setupScrollIndicator() {
        addSubview(scrollIndicator)
        setup(stateConfig: configuration.indicator.normalState, indicatorTextConfig: nil)
    }

    private func setup(
        stateConfig: DMScrollBar.Configuration.Indicator.StateConfig,
        indicatorTextConfig: DMScrollBar.Configuration.Indicator.ActiveStateConfig.TextConfig?
    ) {
        let scrollIndicatorInitialDistance: CGFloat
        switch configuration.direction {
        case .horizontal:
            scrollIndicatorInitialDistance = configuration.indicator.animation.animationType == .fadeAndSide && !configuration.isAlwaysVisible && alpha == 0 ?
                stateConfig.size.height :
                -stateConfig.insets.bottom
            setupConstraint(
                constraint: &scrollIndicatorBottomConstraint,
                build: { scrollIndicator.bottomAnchor.constraint(equalTo: bottomAnchor, constant: $0) },
                value: scrollIndicatorInitialDistance
            )
            setupConstraint(
                constraint: &scrollIndicatorHeightConstraint,
                build: { scrollIndicator.heightAnchor.constraint(equalToConstant: $0) },
                value: stateConfig.size.height
            )
            setupConstraint(
                constraint: &scrollIndicatorWidthConstraint,
                build: scrollIndicator.widthAnchor.constraint(equalToConstant:),
                value: stateConfig.size.width
            )
            if scrollIndicatorLeadingConstraint == nil {
                let leadingOffset = scrollIndicatorOffsetFromScrollOffset(
                    scrollView?.contentOffset.x ?? 0,
                    shouldAdjustOverscrollOffset: false,
                    direction: .horizontal
                )
                scrollIndicatorLeadingConstraint = scrollIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingOffset)
                scrollIndicatorLeadingConstraint?.isActive = true
            }
        case .vertical:
            scrollIndicatorInitialDistance = configuration.indicator.animation.animationType == .fadeAndSide && !configuration.isAlwaysVisible && alpha == 0 ?
                stateConfig.size.width :
                -stateConfig.insets.right
            setupConstraint(
                constraint: &scrollIndicatorTrailingConstraint,
                build: { scrollIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: $0) },
                value: scrollIndicatorInitialDistance
            )
            setupConstraint(
                constraint: &scrollIndicatorWidthConstraint,
                build: { scrollIndicator.widthAnchor.constraint(greaterThanOrEqualToConstant: $0) },
                value: stateConfig.size.width
            )
            setupConstraint(
                constraint: &scrollIndicatorHeightConstraint,
                build: scrollIndicator.heightAnchor.constraint(equalToConstant:),
                value: stateConfig.size.height
            )
            if scrollIndicatorTopConstraint == nil {
                let topOffset = scrollIndicatorOffsetFromScrollOffset(
                    scrollView?.contentOffset.y ?? 0,
                    shouldAdjustOverscrollOffset: false,
                    direction: .vertical
                )
                scrollIndicatorTopConstraint = scrollIndicator.topAnchor.constraint(equalTo: topAnchor, constant: topOffset)
                scrollIndicatorTopConstraint?.isActive = true
            }
        }

        scrollIndicator.setup(
            stateConfig: stateConfig,
            textConfig: indicatorTextConfig,
            accessibilityIdentifier: configuration.indicator.accessibilityIdentifier
        )
    }

    private func setupAdditionalInfoView() {
        guard let infoLabelConfig = configuration.infoLabel else { return }
        addSubview(infoView)
        infoView.setup(config: infoLabelConfig)
        switch configuration.direction {
        case .horizontal:
            let offsetLabelInitialDistance = infoLabelConfig.animation.animationType == .fadeAndSide ? 0 : infoLabelConfig.distanceToScrollIndicator
            infoViewToScrollIndicatorConstraint = scrollIndicator.topAnchor.constraint(equalTo: infoView.bottomAnchor, constant: offsetLabelInitialDistance)
            infoViewToScrollIndicatorConstraint?.isActive = true
            if let maximumWidth = infoLabelConfig.maximumWidth {
                infoView.heightAnchor.constraint(lessThanOrEqualToConstant: maximumWidth).isActive = true
            } else if let scrollViewLayoutGuide {
                infoView.topAnchor.constraint(greaterThanOrEqualTo: scrollViewLayoutGuide.topAnchor, constant: 8).isActive = true
            }
            infoView.centerXAnchor.constraint(equalTo: scrollIndicator.centerXAnchor).isActive = true
        case .vertical:
            let offsetLabelInitialDistance = infoLabelConfig.animation.animationType == .fadeAndSide ? 0 : infoLabelConfig.distanceToScrollIndicator
            infoViewToScrollIndicatorConstraint = scrollIndicator.leadingAnchor.constraint(equalTo: infoView.trailingAnchor, constant: offsetLabelInitialDistance)
            infoViewToScrollIndicatorConstraint?.isActive = true
            if let maximumWidth = infoLabelConfig.maximumWidth {
                infoView.widthAnchor.constraint(lessThanOrEqualToConstant: maximumWidth).isActive = true
            } else if let scrollViewLayoutGuide {
                infoView.leadingAnchor.constraint(greaterThanOrEqualTo: scrollViewLayoutGuide.leadingAnchor, constant: 8).isActive = true
            }
            infoView.centerYAnchor.constraint(equalTo: scrollIndicator.centerYAnchor).isActive = true
        }
    }

    // MARK: - Scroll view observation

    private func observeScrollViewProperties() {
        scrollView?
            .publisher(for: \.contentOffset)
            .removeDuplicates()
            .withPrevious()
            .dropFirst(2)
            .sink { [weak self] in
                guard let self = self else { return }
                handleScrollViewOffsetChange(previousOffset: $0, newOffset: $1, direction: configuration.direction)
            }
            .store(in: &cancellables)
        scrollView?
            .panGestureRecognizer
            .publisher(for: \.state)
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] in self?.handleScrollViewGestureState($0) }
            .store(in: &cancellables)
        /// Next observation is needed to keep scrollBar always on top, when new subviews are added to the scrollView.
        /// For example, when adding scrollBar to the tableView, the tableView section headers overlaps scrollBar, and therefore scrollBar gestures are not recognized.
        /// layer.sublayers property is used for observation because subviews property is not KVO compliant.
        scrollView?
            .publisher(for: \.layer.sublayers)
            .sink { [weak self] _ in self?.bringScrollBarToFront() }
            .store(in: &cancellables)
    }

    private func bringScrollBarToFront() {
        guard let scrollView else { return }

        let numberOfScrollBars = scrollView.subviews.filter { $0.isKind(of: DMScrollBar.self) }.count

        switch numberOfScrollBars {
        case 1:
            if let lastSubview = scrollView.layer.sublayers?.last?.delegate, !lastSubview.isKind(of: DMScrollBar.self) {
                scrollView.bringSubviewToFront(self)
            }
        case 2:
            let isTopSubview = scrollView.layer.sublayers?.last?.delegate?.isKind(of: DMScrollBar.self) ?? false
            let isSecondTopSubview = scrollView.layer.sublayers?.lastlast?.delegate?.isKind(of: DMScrollBar.self) ?? false
            switch (isTopSubview, isSecondTopSubview) {
            case (false, false):
                scrollView.bringSubviewToFront(self)
            case (true, false):
                if let index = scrollView.subviews.firstIndex(of: self) {
                    scrollView.exchangeSubview(at: index, withSubviewAt: scrollView.subviews.count - 2)
                }
            case (false, true):
                if let index = scrollView.subviews.firstIndex(of: self) {
                    scrollView.exchangeSubview(at: index, withSubviewAt: scrollView.subviews.count - 1)
                }
            case (true, true):
                break
            }
            if !isTopSubview || !isSecondTopSubview {
                scrollView.bringSubviewToFront(self)
            }
        default:
            scrollView.bringSubviewToFront(self)
        }
    }

    private func handleScrollViewOffsetChange(previousOffset: CGPoint?, newOffset: CGPoint, direction: Configuration.Direction) {
        guard maxScrollViewOffset(direction: direction) > 30 else { return } // Content size should be 30px larger than scrollView.height
        animateScrollBarShow(direction: direction)
        switch direction {
        case .horizontal:
            scrollIndicatorLeadingConstraint?.constant = scrollIndicatorOffsetFromScrollOffset(
                newOffset.x,
                shouldAdjustOverscrollOffset: panGestureRecognizer?.state == .possible && decelerateAnimation == nil,
                direction: direction
            )
        case .vertical:
            scrollIndicatorTopConstraint?.constant = scrollIndicatorOffsetFromScrollOffset(
                newOffset.y,
                shouldAdjustOverscrollOffset: panGestureRecognizer?.state == .possible && decelerateAnimation == nil,
                direction: direction
            )
        }
        startHideTimerIfNeeded(direction: direction)
        /// Next code is needed to keep additional info label and scroll bar titles up-to-date during scroll view decelerate
        guard isPanGestureInactive else { return }
        if infoView.alpha == 1 {
            switch direction {
            case .horizontal:
                updateAdditionalInfoViewState(forScrollOffset: newOffset.x, previousOffset: previousOffset?.x, direction: .horizontal)
            case .vertical:
                updateAdditionalInfoViewState(forScrollOffset: newOffset.y, previousOffset: previousOffset?.y, direction: .vertical)
            }
        }
        if scrollIndicator.isIndicatorLabelVisible {
            updateScrollIndicatorText(
                forScrollOffset: direction == .horizontal ? newOffset.x : newOffset.y,
                previousOffset: direction == .horizontal ? previousOffset?.x : previousOffset?.y,
                textConfig: configuration.indicator.activeState.textConfig,
                direction: direction
            )
        }
    }

    private func handleScrollViewGestureState(_ state: UIGestureRecognizer.State) {
        invalidateDecelerateAnimation()
        animateAdditionalInfoViewHide()
    }

    // MARK: - Gesture Recognizers

    private func addGestureRecognizers() {
        let panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture))
        panGestureRecognizer.delegate = self
        addGestureRecognizer(panGestureRecognizer)
        self.panGestureRecognizer = panGestureRecognizer

        let longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPressGesture))
        longPressGestureRecognizer.minimumPressDuration = 0.2
        longPressGestureRecognizer.delegate = self
        addGestureRecognizer(longPressGestureRecognizer)
        self.longPressGestureRecognizer = longPressGestureRecognizer

        scrollView?.gestureRecognizers?.forEach {
            $0.require(toFail: panGestureRecognizer)
            $0.require(toFail: longPressGestureRecognizer)
        }
    }

    @objc private func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
        let direction = configuration.direction
        switch recognizer.state {
        case .began: handlePanGestureBegan(recognizer, direction: direction)
        case .changed: handlePanGestureChanged(recognizer, direction: direction)
        case .ended, .cancelled, .failed: handlePanGestureEnded(recognizer, direction: direction)
        default: break
        }
    }

    private func handlePanGestureBegan(_ recognizer: UIPanGestureRecognizer, direction: Configuration.Direction) {
        invalidateDecelerateAnimation()
        switch direction {
        case .horizontal:
            scrollIndicatorOffsetOnGestureStart = scrollIndicatorLeadingConstraint?.constant
        case .vertical:
            scrollIndicatorOffsetOnGestureStart = scrollIndicatorTopConstraint?.constant
        }
        if wasInteractionStartedWithLongPress {
            wasInteractionStartedWithLongPress = false
            longPressGestureRecognizer?.cancel()
        } else {
            gestureInteractionStarted(direction: direction)
        }
    }

    private func handlePanGestureChanged(_ recognizer: UIPanGestureRecognizer, direction: Configuration.Direction) {
        guard let scrollView else { return }
        let offset = recognizer.translation(in: scrollView)
        let scrollIndicatorOffsetOnGestureStart = scrollIndicatorOffsetOnGestureStart ?? 0
        let scrollIndicatorOffset = scrollIndicatorOffsetOnGestureStart + (direction == .horizontal ? offset.x : offset.y)
        let newScrollOffset = scrollOffsetFromScrollIndicatorOffset(scrollIndicatorOffset, direction: direction)
        let previousOffset = scrollView.contentOffset
        switch configuration.direction {
        case .horizontal:
            scrollView.setContentOffset(CGPoint(x: newScrollOffset, y: scrollView.contentOffset.y), animated: false)
            updateAdditionalInfoViewState(forScrollOffset: newScrollOffset, previousOffset: previousOffset.x, direction: .horizontal)
            updateScrollIndicatorText(
                forScrollOffset: newScrollOffset,
                previousOffset: previousOffset.x,
                textConfig: configuration.indicator.activeState.textConfig,
                direction: direction
            )
        case .vertical:
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: newScrollOffset), animated: false)
            updateAdditionalInfoViewState(forScrollOffset: newScrollOffset, previousOffset: previousOffset.y, direction: .vertical)
            updateScrollIndicatorText(
                forScrollOffset: newScrollOffset,
                previousOffset: previousOffset.y,
                textConfig: configuration.indicator.activeState.textConfig,
                direction: direction
            )
        }
    }

    private func handlePanGestureEnded(_ recognizer: UIPanGestureRecognizer, direction: Configuration.Direction) {
        guard let scrollView else { return }
        scrollIndicatorOffsetOnGestureStart = nil
        let velocity = direction == .horizontal ? recognizer.velocity(in: scrollView).withZeroY : recognizer.velocity(in: scrollView).withZeroX
        let isSignificantVelocity = configuration.direction == .horizontal ? abs(velocity.x) > 100 : abs(velocity.y) > 100
        let contentOffset = configuration.direction == .horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
        let isOffsetInScrollBounds = maxScrollViewOffset(direction: direction) > minScrollViewOffset(direction: direction) ?
            minScrollViewOffset(direction: direction) ... maxScrollViewOffset(direction: direction) ~= contentOffset :
            false
        gestureInteractionEnded(willDecelerate: isSignificantVelocity || !isOffsetInScrollBounds, direction: direction)
        switch (isSignificantVelocity, isOffsetInScrollBounds) {
        case (true, true): startDeceleration(withVelocity: velocity, direction: direction)
        case (true, false): bounceScrollViewToBoundsIfNeeded(velocity: velocity, direction: direction)
        case (false, true):
            #if !os(visionOS)
            generateHapticFeedback()
            #endif
        case (false, false): bounceScrollViewToBoundsIfNeeded(velocity: .zero, direction: direction)
        }
    }

    @objc private func handleLongPressGesture(_ recognizer: UILongPressGestureRecognizer) {
        let direction = configuration.direction
        switch recognizer.state {
        case .began:
            wasInteractionStartedWithLongPress = true
            gestureInteractionStarted(direction: direction)
        case .cancelled where panGestureRecognizer?.state.isInactive == true:
            gestureInteractionEnded(willDecelerate: false, direction: direction)
            #if !os(visionOS)
            generateHapticFeedback()
            #endif
        case .ended, .failed:
            gestureInteractionEnded(willDecelerate: false, direction: direction)
            #if !os(visionOS)
            generateHapticFeedback()
            #endif
        default: break
        }
    }

    private func gestureInteractionStarted(direction: Configuration.Direction) {
        let scrollOffset = scrollOffsetFromScrollIndicatorOffset((direction == .horizontal ? scrollIndicatorLeadingConstraint?.constant : scrollIndicatorTopConstraint?.constant) ?? 0, direction: direction)
        updateAdditionalInfoViewState(forScrollOffset: scrollOffset, previousOffset: nil, direction: direction)
        invalidateHideTimer()
        #if !os(visionOS)
        generateHapticFeedback()
        #endif
        updateScrollIndicatorText(
            forScrollOffset: scrollOffset,
            previousOffset: nil,
            textConfig: configuration.indicator.activeState.textConfig,
            direction: direction
        )
        switch configuration.indicator.activeState {
        case .unchanged: break
        case let .scaled(factor): animateIndicatorStateChange(to: configuration.indicator.normalState.applying(scaleFactor: factor), textConfig: nil)
        case let .custom(config, textConfig): animateIndicatorStateChange(to: config, textConfig: textConfig)
        }
    }

    private func gestureInteractionEnded(willDecelerate: Bool, direction: Configuration.Direction) {
        startHideTimerIfNeeded(direction: direction)
        switch configuration.indicator.activeState {
        case .unchanged: return
        case let .custom(_, textConfig) where textConfig != nil && willDecelerate: return
        case .custom, .scaled: animateIndicatorStateChange(to: configuration.indicator.normalState, textConfig: nil)
        }
    }

    private func animateIndicatorStateChange(
        to stateConfig: DMScrollBar.Configuration.Indicator.StateConfig,
        textConfig: DMScrollBar.Configuration.Indicator.ActiveStateConfig.TextConfig?
    ) {
        animate(duration: configuration.indicator.stateChangeAnimationDuration) { [weak self] in
            self?.setup(stateConfig: stateConfig, indicatorTextConfig: textConfig)
            self?.layoutIfNeeded()
        }
    }

    // MARK: - Deceleration & Bounce animations

    private var scale: CGFloat {
        #if os(visionOS)
        1
        #else
        UIScreen.main.scale
        #endif
    }

    private func startDeceleration(withVelocity velocity: CGPoint, direction: Configuration.Direction) {
        guard let scrollView else { return }
        let parameters = DecelerationTimingParameters(
            initialValue: scrollIndicatorOffset,
            initialVelocity: velocity,
            decelerationRate: UIScrollView.DecelerationRate.normal.rawValue,
            threshold: 0.5 / scale
        )

        let destination = parameters.destination
        let intersection = getIntersection(
            rect: scrollIndicatorOffsetBounds,
            segment: (scrollIndicatorOffset, destination)
        )

        let duration: TimeInterval = {
            if let intersection, let intersectionDuration = parameters.duration(to: intersection) {
                return intersectionDuration
            } else {
                return parameters.duration
            }
        }()

        guard configuration.shouldDecelerate else { return }

        decelerateAnimation = TimerAnimation(
            duration: duration,
            animations: { [weak self] _, time in
                guard let self else { return }
                switch direction {
                case .horizontal:
                    let newX = self.scrollOffsetFromScrollIndicatorOffset(parameters.value(at: time).x, direction: .horizontal)
                    if abs(scrollView.contentOffset.x - newX) < parameters.threshold { return }
                    scrollView.setContentOffset(CGPoint(x: newX, y: scrollView.contentOffset.y), animated: false)
                case .vertical:
                    let newY = self.scrollOffsetFromScrollIndicatorOffset(parameters.value(at: time).y, direction: .vertical)
                    if abs(scrollView.contentOffset.y - newY) < parameters.threshold { return }
                    scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: newY), animated: false)
                }
            }, completion: { [weak self] finished in
                guard let self else { return }
                guard finished, intersection != nil else {
                    self.invalidateDecelerateAnimation()
                    if self.configuration.indicator.activeState.textConfig != nil {
                        self.animateIndicatorStateChange(to: self.configuration.indicator.normalState, textConfig: nil)
                    }
                    return
                }
                let velocity = parameters.velocity(at: duration)
                self.bounce(withVelocity: velocity, direction: direction)
            }
        )
    }

    private func bounce(withVelocity velocity: CGPoint, spring: Spring = .default, direction: Configuration.Direction) {
        guard let scrollView else { return }
        let velocityMultiplier = interval(1, maxScrollViewOffset(direction: direction) / maxScrollIndicatorOffset(direction: direction), 30)
        let velocity = interval(-7000, velocity.y * velocityMultiplier, 7000)
        var previousScrollViewOffsetBounds = scrollViewOffsetBounds
        var restOffset = scrollView.contentOffset.clamped(to: scrollViewOffsetBounds)
        let displacement = scrollView.contentOffset - restOffset
        let threshold = 0.5 / scale
        var previousSafeInset = scrollView.safeAreaInsets

        let parameters = SpringTimingParameters(
            spring: spring,
            displacement: displacement,
            initialVelocity: CGPoint(x: velocity, y: velocity),
            threshold: threshold
        )

        decelerateAnimation = TimerAnimation(
            duration: parameters.duration,
            animations: { _, time in
                switch direction {
                case .horizontal:
                    let leftSafeInsetDif = previousSafeInset.left - scrollView.safeAreaInsets.left
                    let rightSafeInsetDif = previousSafeInset.right - scrollView.safeAreaInsets.right
                    previousScrollViewOffsetBounds = previousScrollViewOffsetBounds.inset(by: UIEdgeInsets(top: 0, left: leftSafeInsetDif, bottom: 0, right: rightSafeInsetDif))
                    restOffset.x += self.scrollViewOffsetBounds.width - previousScrollViewOffsetBounds.width + leftSafeInsetDif + rightSafeInsetDif
                    previousScrollViewOffsetBounds = self.scrollViewOffsetBounds
                    previousSafeInset = scrollView.safeAreaInsets
                    let offset = restOffset + parameters.value(at: time)
                    scrollView.setContentOffset(offset, animated: false)
                case .vertical:
                    let topSafeInsetDif = previousSafeInset.top - scrollView.safeAreaInsets.top
                    let bottomSafeInsetDif = previousSafeInset.bottom - scrollView.safeAreaInsets.bottom
                    previousScrollViewOffsetBounds = previousScrollViewOffsetBounds.inset(by: UIEdgeInsets(top: topSafeInsetDif, left: 0, bottom: bottomSafeInsetDif, right: 0))
                    restOffset.y += self.scrollViewOffsetBounds.height - previousScrollViewOffsetBounds.height + topSafeInsetDif + bottomSafeInsetDif
                    previousScrollViewOffsetBounds = self.scrollViewOffsetBounds
                    previousSafeInset = scrollView.safeAreaInsets
                    let offset = restOffset + parameters.value(at: time)
                    scrollView.setContentOffset(offset, animated: false)
                }
            },
            completion: { [weak self] _ in
                guard let self else { return }
                self.invalidateDecelerateAnimation()
                if self.configuration.indicator.activeState.textConfig == nil { return }
                self.animateIndicatorStateChange(to: self.configuration.indicator.normalState, textConfig: nil)
            }
        )
    }

    private func bounceScrollViewToBoundsIfNeeded(velocity: CGPoint, direction: Configuration.Direction) {
        guard let scrollView else { return }
        let overscroll: CGFloat = {
            switch direction {
            case .horizontal:
                if scrollView.contentOffset.x < minScrollViewOffset(direction: .horizontal) {
                    return minScrollViewOffset(direction: .horizontal) - scrollView.contentOffset.x
                } else if scrollView.contentOffset.x > maxScrollViewOffset(direction: .horizontal) {
                    return scrollView.contentOffset.x - maxScrollViewOffset(direction: .horizontal)
                }
            case .vertical:
                if scrollView.contentOffset.y < minScrollViewOffset(direction: .vertical) {
                    return minScrollViewOffset(direction: .vertical) - scrollView.contentOffset.y
                } else if scrollView.contentOffset.y > maxScrollViewOffset(direction: .vertical) {
                    return scrollView.contentOffset.y - maxScrollViewOffset(direction: .vertical)
                }
            }
            return 0
        }()
        if overscroll == 0 { return }
        let additionalStiffness = if direction == .horizontal { (overscroll / scrollView.frame.width) * 400 } else { (overscroll / scrollView.frame.height) * 400 }
        bounce(withVelocity: velocity, spring: Spring(mass: 1, stiffness: 100 + additionalStiffness, dampingRatio: 1), direction: direction)
    }

    private func invalidateDecelerateAnimation() {
        decelerateAnimation?.invalidate()
        decelerateAnimation = nil
    }

    // MARK: - Calculations

    private var minScrollIndicatorOffsetY: CGFloat {
        return configuration.indicator.normalState.insets.top
    }

    private var maxScrollIndicatorOffsetY: CGFloat {
        return frame.height - configuration.indicator.normalState.size.height - configuration.indicator.normalState.insets.bottom
    }

    private var minScrollIndicatorOffsetX: CGFloat {
        return configuration.indicator.normalState.insets.left
    }

    private var maxScrollIndicatorOffsetX: CGFloat {
        return frame.width - configuration.indicator.normalState.size.width - configuration.indicator.normalState.insets.right
    }

    private var minScrollViewOffsetY: CGFloat {
        guard let scrollView else { return 0 }
        return -scrollView.contentInset.top - scrollView.safeAreaInsets.top
    }

    private var maxScrollViewOffsetY: CGFloat {
        guard let scrollView else { return 0 }
        return scrollView.contentSize.height - scrollView.frame.height + scrollView.safeAreaInsets.bottom + scrollView.contentInset.bottom
    }

    private var minScrollViewOffsetX: CGFloat {
        guard let scrollView else { return 0 }
        return -scrollView.contentInset.left - scrollView.safeAreaInsets.left
    }

    private var maxScrollViewOffsetX: CGFloat {
        guard let scrollView else { return 0 }
        return scrollView.contentSize.width - scrollView.frame.width + scrollView.safeAreaInsets.right + scrollView.contentInset.right
    }

    private func minScrollIndicatorOffset(direction: Configuration.Direction) -> CGFloat {
        direction == .horizontal ? minScrollIndicatorOffsetX : minScrollIndicatorOffsetY
    }

    private func maxScrollIndicatorOffset(direction: Configuration.Direction) -> CGFloat {
        direction == .horizontal ? maxScrollIndicatorOffsetX : maxScrollIndicatorOffsetY
    }

    private func maxScrollViewOffset(direction: Configuration.Direction) -> CGFloat {
        direction == .horizontal ? maxScrollViewOffsetX : maxScrollViewOffsetY
    }

    private func minScrollViewOffset(direction: Configuration.Direction) -> CGFloat {
        direction == .horizontal ? minScrollViewOffsetX : minScrollViewOffsetY
    }

    private var scrollIndicatorOffsetBounds: CGRect {
        CGRect(
            x: minScrollIndicatorOffset(direction: .horizontal),
            y: minScrollIndicatorOffset(direction: .vertical),
            width: maxScrollIndicatorOffset(direction: .horizontal) - minScrollIndicatorOffset(direction: .horizontal),
            height: maxScrollIndicatorOffset(direction: .vertical) - minScrollIndicatorOffset(direction: .vertical)
        )
    }

    private var scrollViewOffsetBounds: CGRect {
        CGRect(
            x: minScrollViewOffset(direction: .horizontal),
            y: minScrollViewOffset(direction: .vertical),
            width: maxScrollViewOffset(direction: .horizontal) - minScrollViewOffset(direction: .horizontal),
            height: maxScrollViewOffset(direction: .vertical) - minScrollViewOffset(direction: .vertical)
        )
    }

    private var scrollIndicatorOffset: CGPoint {
        CGPoint(x: scrollIndicatorLeadingConstraint?.constant ?? 0, y: scrollIndicatorTopConstraint?.constant ?? 0)
    }

    private func scrollOffsetFromScrollIndicatorOffset(_ scrollIndicatorOffset: CGFloat, direction: Configuration.Direction) -> CGFloat {
        let adjustedScrollIndicatorOffset = adjustedScrollIndicatorOffsetForOverscroll(scrollIndicatorOffset, isPanGestureSource: true, direction: direction)
        let scrollIndicatorOffsetPercent = (adjustedScrollIndicatorOffset - minScrollIndicatorOffset(direction: direction)) / (maxScrollIndicatorOffset(direction: direction) - minScrollIndicatorOffset(direction: direction))
        let scrollOffset = scrollIndicatorOffsetPercent * (maxScrollViewOffset(direction: direction) - minScrollViewOffset(direction: direction)) + minScrollViewOffset(direction: direction)

        return scrollOffset
    }

    private func scrollIndicatorOffsetFromScrollOffset(_ scrollOffset: CGFloat, shouldAdjustOverscrollOffset: Bool, direction: Configuration.Direction) -> CGFloat {
        let scrollOffsetPercent = (scrollOffset - minScrollViewOffset(direction: direction)) / (maxScrollViewOffset(direction: direction) - minScrollViewOffset(direction: direction))
        let scrollIndicatorOffset = scrollOffsetPercent * (maxScrollIndicatorOffset(direction: direction) - minScrollIndicatorOffset(direction: direction)) + minScrollIndicatorOffset(direction: direction)

        return shouldAdjustOverscrollOffset ?
            adjustedScrollIndicatorOffsetForOverscroll(scrollIndicatorOffset, isPanGestureSource: false, direction: direction) :
            scrollIndicatorOffset
    }

    private func adjustedScrollIndicatorOffsetForOverscroll(_ offset: CGFloat, isPanGestureSource: Bool, direction: Configuration.Direction) -> CGFloat {
        let indicatorToScrollRatio = scrollIndicatorOffsetBounds.height / scrollViewOffsetBounds.height
        let coefficient = isPanGestureSource ?
            RubberBand.defaultCoefficient * indicatorToScrollRatio :
            RubberBand.defaultCoefficient / indicatorToScrollRatio
        let adjustedCoefficient = interval(0.1, coefficient, RubberBand.defaultCoefficient)

        switch direction {
        case .horizontal:
            return RubberBand(
                coeff: adjustedCoefficient,
                dims: frame.size,
                bounds: scrollIndicatorOffsetBounds
            ).clamp(CGPoint(x: offset, y: 0)).x
        case .vertical:
            return RubberBand(
                coeff: adjustedCoefficient,
                dims: frame.size,
                bounds: scrollIndicatorOffsetBounds
            ).clamp(CGPoint(x: 0, y: offset)).y
        }
    }

    // MARK: - Private methods

    private var isPanGestureInactive: Bool {
        return panGestureRecognizer?.state.isInactive == true
    }

    private func scrollIndicatorOffset(forContentOffset contentOffset: CGFloat, direction: Configuration.Direction) -> CGFloat {
        switch direction {
        case .horizontal:
            return contentOffset + scrollIndicatorOffset.x + infoView.frame.width / 2
        case .vertical:
            return contentOffset + scrollIndicatorOffset.y + infoView.frame.height / 2
        }
    }

    private func startHideTimerIfNeeded(direction: Configuration.Direction) {
        guard isPanGestureInactive else { return }
        invalidateHideTimer()
        hideTimer = Timer.scheduledTimer(
            withTimeInterval: configuration.hideTimeInterval,
            repeats: false
        ) { [weak self] _ in
            self?.animateScrollBarHide(direction: direction)
            self?.invalidateHideTimer()
        }
    }

    private func invalidateHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func updateAdditionalInfoViewState(forScrollOffset scrollViewOffset: CGFloat, previousOffset: CGFloat?, direction: Configuration.Direction) {
        if configuration.infoLabel == nil { return }
        guard let offsetLabelText = delegate?.infoLabelText(
            forContentOffset: scrollViewOffset,
            scrollIndicatorOffset: scrollIndicatorOffset(forContentOffset: scrollViewOffset, direction: direction)
        ) else { return animateAdditionalInfoViewHide() }
        animateAdditionalInfoViewShow()
        let direction: CATransitionSubtype? = {
            guard let previousOffset else { return nil }
            switch direction {
            case .horizontal:
                return scrollViewOffset > previousOffset ? .fromLeft : .fromRight
            case .vertical:
                return scrollViewOffset > previousOffset ? .fromTop : .fromBottom
            }
        }()
        infoView.updateText(text: offsetLabelText, direction: direction)
    }

    private func updateScrollIndicatorText(
        forScrollOffset scrollViewOffset: CGFloat,
        previousOffset: CGFloat?,
        textConfig: DMScrollBar.Configuration.Indicator.ActiveStateConfig.TextConfig?,
        direction scrollDirection: Configuration.Direction
    ) {
        let direction: CATransitionSubtype? = {
            guard let previousOffset else { return nil }
            switch scrollDirection {
            case .horizontal:
                return scrollViewOffset > previousOffset ? .fromLeft : .fromRight
            case .vertical:
                return scrollViewOffset > previousOffset ? .fromTop : .fromBottom
            }
        }()
        scrollIndicator.updateScrollIndicatorText(
            direction: direction,
            scrollBarLabelText: delegate?.scrollBarText(
                forContentOffset: scrollViewOffset,
                scrollIndicatorOffset: scrollIndicatorOffset(forContentOffset: scrollViewOffset, direction: scrollDirection)
            ),
            textConfig: textConfig
        )
    }

    private func animateScrollBarShow(direction: Configuration.Direction) {
        guard alpha == 0 else { return }
        setup(stateConfig: configuration.indicator.normalState, indicatorTextConfig: nil)
        layoutIfNeeded()
        animate(duration: configuration.indicator.animation.showDuration) { [weak self] in
            guard let self else { return }
            self.alpha = 1
            guard self.configuration.indicator.animation.animationType == .fadeAndSide else { return }
            switch direction {
            case .horizontal:
                self.scrollIndicatorBottomConstraint?.constant = -self.configuration.indicator.normalState.insets.bottom
            case .vertical:
                self.scrollIndicatorTrailingConstraint?.constant = -self.configuration.indicator.normalState.insets.right
            }
            self.layoutIfNeeded()
        }
    }

    private func animateScrollBarHide(direction: Configuration.Direction) {
        if alpha == 0 { return }
        defer { animateAdditionalInfoViewHide() }
        if configuration.isAlwaysVisible { return }
        animate(duration: configuration.indicator.animation.hideDuration) { [weak self] in
            guard let self else { return }
            self.alpha = 0
            guard self.configuration.indicator.animation.animationType == .fadeAndSide else { return }
            switch direction {
            case .horizontal:
                self.scrollIndicatorBottomConstraint?.constant = self.configuration.indicator.normalState.size.height
            case .vertical:
                self.scrollIndicatorTrailingConstraint?.constant = self.configuration.indicator.normalState.size.width
            }
            self.layoutIfNeeded()
        }
    }

    private func animateAdditionalInfoViewShow() {
        guard let infoLabelConfig = configuration.infoLabel, infoView.alpha == 0 else { return }
        animate(duration: infoLabelConfig.animation.showDuration) { [weak self] in
            self?.infoView.alpha = 1
            guard infoLabelConfig.animation.animationType == .fadeAndSide else { return }
            self?.infoViewToScrollIndicatorConstraint?.constant = infoLabelConfig.distanceToScrollIndicator
            self?.layoutIfNeeded()
        }
    }

    private func animateAdditionalInfoViewHide() {
        guard let infoLabelConfig = configuration.infoLabel, infoView.alpha != 0 else { return }
        animate(duration: infoLabelConfig.animation.hideDuration) { [weak self] in
            self?.infoView.alpha = 0
            guard infoLabelConfig.animation.animationType == .fadeAndSide else { return }
            self?.infoViewToScrollIndicatorConstraint?.constant = 0
            self?.layoutIfNeeded()
        }
    }

    private func animate(duration: CGFloat, animation: @escaping () -> Void) {
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: 1,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut],
            animations: animation
        )
    }
}

// MARK: - UIGestureRecognizerDelegate

extension DMScrollBar: UIGestureRecognizerDelegate {
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return gestureRecognizer == panGestureRecognizer && otherGestureRecognizer == longPressGestureRecognizer ||
            gestureRecognizer == longPressGestureRecognizer && otherGestureRecognizer == panGestureRecognizer
    }

    public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        switch configuration.direction {
        case .horizontal:
            return scrollIndicator.frame.minX ... scrollIndicator.frame.maxX ~= touch.location(in: self).x
        case .vertical:
            return scrollIndicator.frame.minY ... scrollIndicator.frame.maxY ~= touch.location(in: self).y
        }
    }
}
