//
//  SyncPrint.swift
//  SwiftyLua
//
//  Created by hanzhao on 2017/5/30.
//  Copyright © 2017年 hanzhao. All rights reserved.
//

import Foundation

//
//  syncprint.swift
//
//  Created by Guillaume Lessard on 2014-08-22.
//  Copyright (c) 2016 Guillaume Lessard. All rights reserved.
//
//  https://github.com/glessard/syncprint
//  https://gist.github.com/glessard/826241431dcea3655d1e
//

import Dispatch
import Foundation.NSThread

/*
private let PrintQueue = DispatchQueue(label: "com.tffenterprises.syncprint")
private let PrintGroup = DispatchGroup()

private var silenceOutput: Int32 = 0

///  A wrapper for `Swift.print()` that executes all requests on a serial queue.
///  Useful for logging from multiple threads.
///
///  Writes a basic thread identifier (main or back), the textual representation
///  of `item`, and a newline character onto the standard output.
///
///  The textual representation is from the `String` initializer, `String(item)`
///
///  - parameter item: the item to be printed

public func sync_do(_ f: @escaping (String) -> ())
{
    let thread = Thread.current.isMainThread ? "[main]" : "[back \(Thread.current.id)]"

    PrintQueue.async(group: PrintGroup) {
        // Read silenceOutput atomically
        if OSAtomicAdd32(0, &silenceOutput) == 0
        {
            // print(thread, item, separator: " ")
            f(thread)
        }
    }
}

func sync_print(_ item: Any) {
    sync_do { t in
        print(t, item, separator: " ")
    }
}

///  Block until all tasks created by syncprint() have completed.

public func syncprintwait()
{
    // Wait at most 200ms for the last messages to print out.
    let res = PrintGroup.wait(timeout: DispatchTime.now() + 0.2)
    if res == .timedOut
    {
        OSAtomicIncrement32Barrier(&silenceOutput)
        PrintGroup.notify(queue: PrintQueue) {
            print("Skipped output")
            OSAtomicDecrement32Barrier(&silenceOutput)
        }
    }
}
*/
