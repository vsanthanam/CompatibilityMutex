// CompatibilityMutex
// CompatibilityMutex.swift
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

import Foundation
import Synchronization

/// A synchronization primitive that protects shared mutable state via mutual exclusion.
///
/// The `CompatibilityMutex` type offers non-recursive exclusive access to the state it is protecting by blocking threads attempting to acquire the lock.
/// Only one execution context at a time has access to the value stored within the `CompatibilityMutex` allowing for exclusive access.
///
/// An example use of `CompatibilityMutex` in a class used simultaneously by many threads protecting a `Dictionary` value:
///
/// ```swift
/// class Manager {
///     let cache = CompatibilityMutex<[Key: Resource]>([:])
///
///     func saveResource(_ resource: Resource, as key: Key) {
///         cache.withLock {
///             $0[key] = resource
///         }
///     }
/// }
/// ```
///
/// Unlike Apple's `Synchronization.Mutex`, `CompatibilityMutex` works older Apple platforms, up to iOS 15`.
@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, watchOS 8.0, tvOS 15.0, visionOS 1.0, *)
public struct CompatibilityMutex<Value>: ~Copyable where Value: ~Copyable {

    // MARK: - Initializers

    /// Initializes a value of this mutex with the given initial state.
    /// - Parameter initialValue: The initial value to give to the mutex.
    public init(
        _ initialValue: consuming sending Value
    ) {
        if #available(macOS 15.0, macCatalyst 18.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            let pointer = UnsafeMutablePointer<Mutex<Value>>.allocate(capacity: 1)
            pointer.initialize(to: Mutex(initialValue))
            storage = UnsafeMutableRawPointer(pointer)
            usesMutex = true
        } else {
            let pointer = UnsafeMutablePointer<LockBox>.allocate(capacity: 1)
            pointer.initialize(to: LockBox(value: initialValue))
            storage = UnsafeMutableRawPointer(pointer)
            usesMutex = false
        }
    }

    // MARK: - API

    // Swift 6.2 toolchains on non-Apple platforms have slightly different region isolation rules that do not properly forward `sending` from the `inout`.
    // Swift 6.2.4 in Xcode fixes this, and Swift 6.3 fixes it for non-Apple platforms, too.
    // The body of these two functions are identical, save for this requirement.
    // We will drop this when we drop support for Swift 6.2.x
    #if compiler(>=6.3)
        /// Calls the given closure after acquiring the lock and then releases ownership.
        ///
        /// This method is equivalent to the following sequence of code:
        ///
        /// ```swift
        /// mutex.lock()
        /// defer {
        ///     mutex.unlock()
        /// }
        /// ```
        /// - Warning: Recursive calls to `withLock` within the closure parameter has behavior that is platform dependent. Some platforms may choose to panic the process, deadlock, or leave this behavior unspecified. This will never reacquire the lock however.
        /// - Parameter body: A closure with a parameter of Value that has exclusive access to the value being stored within this mutex.
        /// This closure is considered the critical section as it will only be executed once the calling thread has acquired the lock.
        /// - Returns: The return value, if any, of the body closure parameter.
        public borrowing func withLock<Result, Failure>(
            _ body: (inout sending Value) throws(Failure) -> sending Result
        ) throws(Failure) -> sending Result where Result: ~Copyable, Failure: Error {
            if usesMutex, #available(macOS 15.0, macCatalyst 18.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
                let pointer = storage.assumingMemoryBound(to: Mutex<Value>.self)
                return try pointer.pointee.withLock { (value: inout sending Value) throws(Failure) -> sending Result in
                    try body(&value)
                }
            } else {
                let pointer = storage.assumingMemoryBound(to: LockBox.self)
                pointer.pointee.lock.lock()
                defer {
                    pointer.pointee.lock.unlock()
                }
                return try body(&pointer.pointee.value)
            }
        }
    #else
        /// Calls the given closure after acquiring the lock and then releases ownership.
        ///
        /// This method is equivalent to the following sequence of code:
        ///
        /// ```swift
        /// mutex.lock()
        /// defer {
        ///     mutex.unlock()
        /// }
        /// ```
        /// - Warning: Recursive calls to `withLock` within the closure parameter has behavior that is platform dependent. Some platforms may choose to panic the process, deadlock, or leave this behavior unspecified. This will never reacquire the lock however.
        ///
        /// - Parameter body: A closure with a parameter of `Value` that has exclusive access to the value being stored within this mutex.
        /// This closure is considered the critical section as it will only be executed once the calling thread has acquired the lock.
        /// - Returns: The return value, if any, of the body closure parameter.
        public borrowing func withLock<Result, Failure>(
            _ body: (inout Value) throws(Failure) -> sending Result
        ) throws(Failure) -> sending Result where Result: ~Copyable, Failure: Error {
            if usesMutex, #available(macOS 15.0, macCatalyst 18.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
                let pointer = storage.assumingMemoryBound(to: Mutex<Value>.self)
                return try pointer.pointee.withLock { (value: inout sending Value) throws(Failure) -> sending Result in
                    try body(&value)
                }
            } else {
                let pointer = storage.assumingMemoryBound(to: LockBox.self)
                pointer.pointee.lock.lock()
                defer {
                    pointer.pointee.lock.unlock()
                }
                return try body(&pointer.pointee.value)
            }
        }
    #endif

    // See the comment on `withLock` above regarding the `inout sending` requirement on Swift 6.2.x toolchains.
    #if compiler(>=6.3)
        /// Attempts to acquire the lock and then calls the given closure if successful.
        ///
        /// If the calling thread was successful in acquiring the lock, the closure will be executed and then immediately after it will release ownership of the lock.
        /// If we were unable to acquire the lock, this will return `nil`.
        ///
        /// This method is equivalent to the following sequence of code:
        ///
        /// ```swift
        /// guard mutex.tryLock() else {
        ///     return nil
        /// }
        /// defer {
        ///     mutex.unlock()
        /// }
        /// return try body(&value)
        /// ```
        ///
        /// - Note: This function cannot spuriously fail to acquire the lock. The behavior of similar functions in other languages (such as C’s `mtx_trylock()`) is platform-dependent and may differ from Swift’s behavior.
        ///
        /// - Parameter body: A closure with a parameter of `Value` that has exclusive access to the value being stored within this mutex.
        /// This closure is considered the critical section as it will only be executed if the calling thread acquires the lock.
        /// - Returns: The return value, if any, of the body closure parameter or nil if the lock couldn’t be acquired.
        public borrowing func withLockIfAvailable<Result, Failure>(
            _ body: (inout sending Value) throws(Failure) -> sending Result
        ) throws(Failure) -> sending Result? where Result: ~Copyable, Failure: Error {
            if usesMutex, #available(macOS 15.0, macCatalyst 18.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
                let pointer = storage.assumingMemoryBound(to: Mutex<Value>.self)
                return try pointer.pointee.withLockIfAvailable { (value: inout sending Value) throws(Failure) -> sending Result in
                    try body(&value)
                }
            } else {
                let pointer = storage.assumingMemoryBound(to: LockBox.self)
                guard pointer.pointee.lock.try() else {
                    return nil
                }
                defer {
                    pointer.pointee.lock.unlock()
                }
                return try body(&pointer.pointee.value)
            }
        }
    #else
        /// Attempts to acquire the lock and then calls the given closure if successful.
        ///
        /// If the calling thread was successful in acquiring the lock, the closure will be executed and then immediately after it will release ownership of the lock.
        /// If we were unable to acquire the lock, this will return `nil`.
        ///
        /// This method is equivalent to the following sequence of code:
        ///
        /// ```swift
        /// guard mutex.tryLock() else {
        ///     return nil
        /// }
        /// defer {
        ///     mutex.unlock()
        /// }
        /// return try body(&value)
        /// ```
        ///
        /// - Note: This function cannot spuriously fail to acquire the lock. The behavior of similar functions in other languages (such as C’s `mtx_trylock()`) is platform-dependent and may differ from Swift’s behavior.
        ///
        /// - Parameter body: A closure with a parameter of `Value` that has exclusive access to the value being stored within this mutex.
        /// This closure is considered the critical section as it will only be executed if the calling thread acquires the lock.
        /// - Returns: The return value, if any, of the body closure parameter or nil if the lock couldn’t be acquired.
        public borrowing func withLockIfAvailable<Result, Failure>(
            _ body: (inout Value) throws(Failure) -> sending Result
        ) throws(Failure) -> sending Result? where Result: ~Copyable, Failure: Error {
            if usesMutex, #available(macOS 15.0, macCatalyst 18.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
                let pointer = storage.assumingMemoryBound(to: Mutex<Value>.self)
                return try pointer.pointee.withLockIfAvailable { (value: inout sending Value) throws(Failure) -> sending Result in
                    try body(&value)
                }
            } else {
                let pointer = storage.assumingMemoryBound(to: LockBox.self)
                guard pointer.pointee.lock.try() else {
                    return nil
                }
                defer {
                    pointer.pointee.lock.unlock()
                }
                return try body(&pointer.pointee.value)
            }
        }
    #endif

    // MARK: - Private

    private struct LockBox: ~Copyable {
        let lock = NSLock()
        var value: Value
    }

    private let storage: UnsafeMutableRawPointer
    private let usesMutex: Bool

    deinit {
        if usesMutex, #available(macOS 15.0, macCatalyst 18.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *) {
            let pointer = storage.assumingMemoryBound(to: Mutex<Value>.self)
            // Destroying a `Mutex` in place via `deinitialize(count:)` does not release its stored value.
            // Moving it out and letting it drop as a local does.
            _ = pointer.move()
            pointer.deallocate()
        } else {
            let pointer = storage.assumingMemoryBound(to: LockBox.self)
            pointer.deinitialize(count: 1)
            pointer.deallocate()
        }
    }

}

@available(macOS 12.0, macCatalyst 15.0, iOS 15.0, watchOS 8.0, tvOS 15.0, visionOS 1.0, *)
extension CompatibilityMutex: @unchecked Sendable where Value: ~Copyable {}
