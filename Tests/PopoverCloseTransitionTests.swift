import Testing

@Suite("Popover closing deadline")
@MainActor
struct PopoverCloseTransitionTests {
    @Test("dismissal completes without an animation completion callback")
    func closesIndependently() async {
        let transition = PopoverCloseTransition(duration: .milliseconds(10))
        var closes = 0
        transition.begin(animate: {}, close: { closes += 1 })
        #expect(transition.isClosing)
        await transition.pendingTask?.value
        #expect(closes == 1)
        #expect(!transition.isClosing)
    }

    @Test("duplicate dismissals neither restart the animation nor close twice")
    func duplicateClose() async {
        let transition = PopoverCloseTransition(duration: .milliseconds(10))
        var animations = 0
        var closes = 0
        let first = transition.begin(animate: { animations += 1 }, close: { closes += 1 })
        let duplicate = transition.begin(animate: { animations += 1 }, close: { closes += 1 })
        #expect(first)
        #expect(!duplicate)
        await transition.pendingTask?.value
        #expect(animations == 1)
        #expect(closes == 1)
    }

    @Test("reopening invalidates the old deadline before a later dismissal")
    func cancelledCloseCannotDismissNewPresentation() async {
        let transition = PopoverCloseTransition(duration: .milliseconds(10))
        var oldCloses = 0
        var newCloses = 0
        transition.begin(animate: {}, close: { oldCloses += 1 })
        let oldTask = transition.pendingTask
        transition.cancel()
        #expect(!transition.isClosing)
        transition.begin(animate: {}, close: { newCloses += 1 })
        await oldTask?.value
        await transition.pendingTask?.value
        #expect(oldCloses == 0)
        #expect(newCloses == 1)
        #expect(!transition.isClosing)
    }

    @Test("synchronous session-end callbacks cannot reenter closing")
    func reentrantClose() async {
        let transition = PopoverCloseTransition(duration: .milliseconds(10))
        var closes = 0
        var duplicateStarted = false
        transition.begin(animate: {
            duplicateStarted = transition.begin(animate: {}, close: { closes += 100 })
        }, close: { closes += 1 })
        #expect(!duplicateStarted)
        await transition.pendingTask?.value
        #expect(closes == 1)
        #expect(!transition.isClosing)
    }
}
