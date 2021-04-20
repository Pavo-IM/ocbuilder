//
//  TaskViewController.swift
//  OCBuilder
//
//  Created by Pavo on 7/27/19.
//  Copyright © 2019 Pavo. All rights reserved.
//

import Cocoa
import ServiceManagement


class TaskViewController: NSViewController {
    
    @IBOutlet var pathLocation: NSPathControl!
    @IBOutlet var outputText: NSTextView!
    @IBOutlet var buildButton: NSButton!
    @IBOutlet var progressBar: NSProgressIndicator!
    @IBOutlet var stopButton: NSButton!
    @IBOutlet weak var versionList: NSPopUpButton!
    let versionArray = ["Debug", "Release", "Debug IA32", "Release IA32"]
    @IBOutlet weak var withKextsChecked: NSButton!

    override func viewDidLoad() {
        stopButton.isEnabled = false
        progressBar.isHidden = true
        super.viewDidLoad()
        if (NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: "com.apple.dt.Xcode") != nil) {
            buildButton.isHidden = false
        } else {
            showCloseAlert()
            buildButton.isHidden = true
            pathLocation.isHidden = true
        }
        versionList.removeAllItems()
        versionList.addItems(withTitles: versionArray)
    }
    
    @objc dynamic var isRunning = false
    var outputPipe:Pipe!
    var buildTask:Process!
    
    @IBAction func startTask(_ sender: Any) {
        stopButton.isEnabled = true
        progressBar.isHidden = false
        outputText.string = ""
        if let repositoryURL = pathLocation.url {
            let cloneLocation = "/tmp"
            let finalLocation = repositoryURL.path
            var arguments:[String] = []
            arguments.append(cloneLocation)
            arguments.append(finalLocation)
            buildButton.isEnabled = false
            progressBar.startAnimation(self)
            if versionList.titleOfSelectedItem == "Debug" {
				arguments.append("Debug")
                arguments.append("X64")
                if withKextsChecked.state == NSControl.StateValue.on {
					arguments.append("1")
                 } else {
					arguments.append("0")
                }
            }
            if versionList.titleOfSelectedItem == "Release" {
                arguments.append("Release")
                arguments.append("X64")
                if withKextsChecked.state == NSControl.StateValue.on {
                    arguments.append("1")
                } else {
                    arguments.append("0")
                }
            }
            if versionList.titleOfSelectedItem == "Debug IA32" {
                arguments.append("Debug")
                arguments.append("Ia32")
                arguments.append("0")
            }
            if versionList.titleOfSelectedItem == "Release IA32" {
                arguments.append("Release")
                arguments.append("Ia32")
                arguments.append("0")
            }
            runOCBuilderScript(arguments)
        }
    }
    
    @IBAction func stopTask(_ sender: NSButton) {
        stopButton.isEnabled = false
        progressBar.isHidden = true
        if isRunning {
            self.progressBar.doubleValue = 0.0
            buildTask.terminate()
        }
    }
    
    func runOCBuilderScript(_ arguments:[String]) {
        isRunning = true
        let taskQueue = DispatchQueue.global(qos: DispatchQoS.QoSClass.background)
        taskQueue.async {
            guard let path = Bundle.main.path(forResource: "runOCBuilderScript",ofType:"command") else {
                print("Unable to locate runOCBuilderScript.command")
                return
            }
            self.buildTask = Process()
            self.buildTask.launchPath = path
            self.buildTask.arguments = arguments
            self.buildTask.terminationHandler = {
                task in
                DispatchQueue.main.async(execute: {
                    self.stopButton.isEnabled = false
                    self.buildButton.isEnabled = true
                    self.progressBar.isHidden = true
                    self.progressBar.stopAnimation(self)
                    self.progressBar.doubleValue = 0.0
                    self.isRunning = false
                })
            }
            self.captureStandardOutput(self.buildTask)
            self.buildTask.launch()
            self.buildTask.waitUntilExit()
        }
    }
    
    func captureStandardOutput(_ task:Process) {
        outputPipe = Pipe()
        task.standardOutput = outputPipe
        outputPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
        NotificationCenter.default.addObserver(forName: NSNotification.Name.NSFileHandleDataAvailable, object: outputPipe.fileHandleForReading , queue: nil) {
            notification in
            let output = self.outputPipe.fileHandleForReading.availableData
            var outputString = String(data: output, encoding: String.Encoding.utf8) ?? ""
            var nextOutput = ""
            DispatchQueue.main.async(execute: {
                let previousOutput = self.outputText.string
                if String(outputString.utf16.prefix(2)) == "\\n" {
                    outputString.remove(at: outputString.startIndex)
                    outputString.remove(at: outputString.startIndex)
                    nextOutput = previousOutput + "\n" + outputString
                } else {
                    nextOutput = previousOutput + outputString
                }
                self.outputText.string = nextOutput
                let range = NSRange(location:nextOutput.count,length:0)
                self.outputText.scrollRangeToVisible(range)
            })
            self.outputPipe.fileHandleForReading.waitForDataInBackgroundAndNotify()
        }
    }
    
    func showCloseAlert() {
        let alert = NSAlert()
        alert.messageText = "Xcode Application is not installed!"
        alert.informativeText = "In order to use OCBuilder you must have the full Xcode application installed. Please install the full Xcode application from https://apps.apple.com/us/app/xcode/id497799835?mt=12."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
