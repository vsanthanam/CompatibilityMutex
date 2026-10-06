// CompatibilityMutex
// CompatibilityMutexTests.swift
//
// MIT License
//
// Copyright (c) 2026 Varun Santhanam
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the  Software), to deal
//
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED  AS IS, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

@testable import CompatibilityMutex
import Foundation
import Testing

@Suite("CompatibilityMutex")
struct CompatibilityMutexTests {

    @Test
    func withLockReturnsBodyResult() {
        let mutex = CompatibilityMutex(42)
        let value = mutex.withLock { $0 }
        #expect(value == 42)
    }

    @Test
    func withLockPersistsMutations() {
        let mutex = CompatibilityMutex([Int]())
        mutex.withLock { $0.append(1) }
        mutex.withLock { $0.append(2) }
        #expect(mutex.withLock { $0 } == [1, 2])
    }

    @Test
    func withLockRethrowsTypedError() {
        let mutex = CompatibilityMutex(0)
        #expect(throws: TestError.boom) {
            try mutex.withLock { (value: inout Int) throws(TestError) in
                value = 1
                throw .boom
            }
        }
        #expect(mutex.withLock { $0 } == 1)
    }

    @Test
    func withLockReleasesLockAfterThrowing() {
        let mutex = CompatibilityMutex(0)
        #expect(throws: TestError.boom) {
            try mutex.withLock { (_: inout Int) throws(TestError) in
                throw .boom
            }
        }
        #expect(mutex.withLockIfAvailable { $0 } == 0)
    }

    @Test
    func withLockSupportsNoncopyableValueAndResult() {
        let mutex = CompatibilityMutex(NoncopyableCounter(count: 0))
        let result = mutex.withLock { counter in
            counter.count += 1
            return NoncopyableCounter(count: counter.count * 10)
        }
        #expect(result.count == 10)
        #expect(mutex.withLock { $0.count } == 1)
    }

    @Test
    func withLockSerializesConcurrentAccess() async {
        let box = Box(CompatibilityMutex(0))
        let iterations = 1000
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< iterations {
                group.addTask {
                    box.mutex.withLock { $0 += 1 }
                }
            }
        }
        #expect(box.mutex.withLock { $0 } == iterations)
    }

    @Test
    func withLockIfAvailableReturnsBodyResultWhenUncontended() {
        let mutex = CompatibilityMutex(42)
        let value = mutex.withLockIfAvailable { value in
            value += 1
            return value
        }
        #expect(value == 43)
        #expect(mutex.withLock { $0 } == 43)
    }

    @Test
    func withLockIfAvailableReturnsNilWhenLockIsHeld() {
        let box = Box(CompatibilityMutex(0))
        let acquired = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)

        let thread = Thread {
            box.mutex.withLock { value in
                acquired.signal()
                release.wait()
                value = 1
            }
            finished.signal()
        }
        thread.start()
        acquired.wait()

        var bodyExecuted = false
        let result = box.mutex.withLockIfAvailable { value in
            bodyExecuted = true
            return value
        }
        #expect(result == nil)
        #expect(!bodyExecuted)

        release.signal()
        finished.wait()

        #expect(box.mutex.withLockIfAvailable { $0 } == 1)
    }

    @Test
    func withLockIfAvailableRethrowsTypedError() {
        let mutex = CompatibilityMutex(0)
        #expect(throws: TestError.boom) {
            try mutex.withLockIfAvailable { (value: inout Int) throws(TestError) in
                value = 1
                throw .boom
            }
        }
        #expect(mutex.withLockIfAvailable { $0 } == 1)
    }

    @Test
    func withLockIfAvailableSupportsNoncopyableValueAndResult() {
        let mutex = CompatibilityMutex(NoncopyableCounter(count: 0))
        let result = mutex.withLockIfAvailable { counter in
            counter.count += 1
            return NoncopyableCounter(count: counter.count * 10)
        }
        guard let result else {
            Issue.record("Expected withLockIfAvailable to acquire an uncontended lock")
            return
        }
        #expect(result.count == 10)
        #expect(mutex.withLock { $0.count } == 1)
    }

    @Test
    func deinitReleasesStoredValue() {
        let flag = Box(CompatibilityMutex(false))
        do {
            let mutex = CompatibilityMutex(DeinitTracker(flag: flag))
            mutex.withLock { _ in }
            #expect(!flag.mutex.withLock { $0 })
        }
        #expect(flag.mutex.withLock { $0 })
    }

    private enum TestError: Error {
        case boom
    }

    private struct NoncopyableCounter: ~Copyable {
        var count: Int
    }

    private final class Box<Value>: Sendable where Value: ~Copyable {
        init(_ mutex: consuming CompatibilityMutex<Value>) {
            self.mutex = mutex
        }

        let mutex: CompatibilityMutex<Value>
    }

    private final class DeinitTracker {
        init(flag: Box<Bool>) {
            self.flag = flag
        }

        deinit {
            flag.mutex.withLock { $0 = true }
        }

        private let flag: Box<Bool>
    }

}
