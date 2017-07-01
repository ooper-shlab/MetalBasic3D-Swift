//
//  AAPLViewController.swift
//  MetalBasic3D
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/11/14.
//
//
/*
 Copyright (C) 2015 Apple Inc. All Rights Reserved.
 See LICENSE.txt for this sample’s licensing information

 Abstract:
 View Controller for Metal Sample Code. Maintains a CADisplayLink timer that runs on the main thread and triggers rendering in AAPLView. Provides update callbacks to its delegate on the timer, prior to triggering rendering.
 */

#if os(iOS)
    import UIKit
    typealias BaseViewController = UIViewController
#else
    import AppKit
    typealias BaseViewController = NSViewController
#endif

// required view controller delegate functions.
@objc(AAPLViewControllerDelegate)
protocol AAPLViewControllerDelegate: NSObjectProtocol {
    
    // Note this method is called from the thread the main game loop is run
    func update(_ controller: AAPLViewController)
    
    // called whenever the main game loop is paused, such as when the app is backgrounded
    func viewController(_ viewController: AAPLViewController, willPause pause: Bool)
}

@objc(AAPLViewController)
class AAPLViewController: BaseViewController {
    
    weak var delegate: AAPLViewControllerDelegate?
    
    // the time interval from the last draw
    private(set) var timeSinceLastDraw: TimeInterval = 0.0
    
    // What vsync refresh interval to fire at. (Sets CADisplayLink frameinterval property)
    // set to 1 by default, which is the CADisplayLink default setting (60 FPS).
    // Setting to 2, will cause gameloop to trigger every other vsync (throttling to 30 FPS)
    var interval: Int = 0
    
    // app control
    
    #if os(iOS)
    private var _displayLink: CADisplayLink?
    #else
    var _displayLink: CVDisplayLink?
    var _displaySource: DispatchSourceUserDataAdd?
    #endif
    
    // boolean to determine if the first draw has occured
    private var _firstDrawOccurred: Bool = false
    
    private var _timeSinceLastDrawPreviousTime: CFTimeInterval = 0.0
    
    // pause/resume
    private var _gameLoopPaused: Bool = false
    
    // our renderer instance
    private var _renderer: AAPLRenderer!
    
    deinit {
        #if os(iOS)
            NotificationCenter.default.removeObserver(self,
                name: .UIApplicationDidEnterBackground,
                object: nil)
            
            NotificationCenter.default.removeObserver(self,
                name: .UIApplicationWillEnterForeground,
                object: nil)
            
        #endif
        if _displayLink != nil {
            self.stopGameLoop()
        }
    }
    
    #if os(iOS)
    private func dispatchGameLoop() {
        // create a game loop timer using a display link
        _displayLink = UIScreen.main.displayLink(withTarget: self,
            selector: #selector(AAPLViewController.gameloop))
        _displayLink?.frameInterval = interval
        _displayLink?.add(to: RunLoop.main,
            forMode: RunLoopMode.defaultRunLoopMode)
    }
    
    #else
    // This is the renderer output callback function
    private let dispatchGameLoop: CVDisplayLinkOutputCallback = {
        displayLink, now, outputTime, flagsIn, flagsOut, displayLinkContext in
        
        let source = Unmanaged<DispatchSourceUserDataAdd>.fromOpaque(displayLinkContext!).takeUnretainedValue()
        source.add(data: 1)
        return kCVReturnSuccess
    }
    #endif
    
    private func initCommon() {
        _renderer = AAPLRenderer()
        self.delegate = _renderer
        
        #if os(iOS)
            let notificationCenter = NotificationCenter.default
            //  Register notifications to start/stop drawing as this app moves into the background
            notificationCenter.addObserver(self,
                selector: #selector(AAPLViewController.didEnterBackground(_:)),
                name: .UIApplicationDidEnterBackground,
                object: nil)
            
            notificationCenter.addObserver(self,
                selector: #selector(AAPLViewController.willEnterForeground(_:)),
                name: .UIApplicationWillEnterForeground,
                object: nil)
            
        #else
            _displaySource = DispatchSource.makeUserDataAddSource(queue: DispatchQueue.main)
            _displaySource!.setEventHandler {[weak self] in
                self?.gameloop()
            }
            _displaySource!.resume()
            
            // Create a display link capable of being used with all active displays
            var cvReturn = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink)
            
            assert(cvReturn == kCVReturnSuccess)
            
            cvReturn = CVDisplayLinkSetOutputCallback(_displayLink!, dispatchGameLoop, Unmanaged.passUnretained(_displaySource!).toOpaque())
            
            assert(cvReturn == kCVReturnSuccess)
            
            cvReturn = CVDisplayLinkSetCurrentCGDisplay(_displayLink!, CGMainDisplayID () )
            
            assert(cvReturn == kCVReturnSuccess)
        #endif
        
        interval = 1
    }
    
    #if os(OSX)
    @objc func _windowWillClose(_ notification: Notification) {
        // Stop the display link when the window is closing because we will
        // not be able to get a drawable, but the display link may continue
        // to fire
        
        if notification.object as AnyObject? === self.view.window {
            CVDisplayLinkStop(_displayLink!)
            _displaySource!.cancel()
        }
    }
    #endif
    
    // Called when loaded from nib
    #if os(iOS)
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        
        self.initCommon()
        
    }
    #else
    override init?(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.initCommon()
    }
    #endif
    
    // called when loaded from storyboard
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.initCommon()
        
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let renderView = self.view as! AAPLView
        renderView.delegate = _renderer
        
        // load all renderer assets before starting game loop
        _renderer.configure(renderView)
        
        #if os(OSX)
            
            let notificationCenter = NotificationCenter.default
            // Register to be notified when the window closes so we can stop the displaylink
            notificationCenter.addObserver(self,
                                           selector: #selector(AAPLViewController._windowWillClose(_:)),
                name: .NSWindowWillClose,
                object: self.view.window)
            
            
            CVDisplayLinkStart(_displayLink!)
        #endif
    }
    
    
    // The main game loop called by the timer above
    @objc func gameloop() {
        
        // tell our delegate to update itself here.
        delegate?.update(self)
        
        if !_firstDrawOccurred {
            // set up timing data for display since this is the first time through this loop
            timeSinceLastDraw             = 0.0
            _timeSinceLastDrawPreviousTime = CACurrentMediaTime()
            _firstDrawOccurred              = true
        } else {
            // figure out the time since we last we drew
            let currentTime = CACurrentMediaTime()
            
            timeSinceLastDraw = currentTime - _timeSinceLastDrawPreviousTime
            
            // keep track of the time interval between draws
            _timeSinceLastDrawPreviousTime = currentTime
        }
        
        // display (render)
        
        assert(self.view is AAPLView)
        
        // call the display method directly on the render view (setNeedsDisplay: has been disabled in the renderview by default)
        (self.view as! AAPLView).display()
    }
    
    // use invalidates the main game loop. when the app is set to terminate
    func stopGameLoop() {
        if _displayLink != nil {
            #if os(iOS)
                _displayLink!.invalidate()
            #else
                // Stop the display link BEFORE releasing anything in the view
                // otherwise the display link thread may call into the view and crash
                // when it encounters something that has been release
                CVDisplayLinkStop(_displayLink!)
                _displaySource!.cancel()
                
                _displayLink = nil
                _displaySource = nil
            #endif
        }
    }
    
    // Used to pause and resume the controller.
    var paused: Bool {
        set(pause) {
            if _gameLoopPaused == pause {
                return
            }
            
            if _displayLink != nil {
                // inform the delegate we are about to pause
                delegate?.viewController(self, willPause: pause)
                
                #if os(iOS)
                    _gameLoopPaused = pause
                    _displayLink!.isPaused = pause
                    if pause {
                        
                        // ask the view to release textures until its resumed
                        (self.view as! AAPLView).releaseTextures()
                    }
                #else
                    if pause {
                        CVDisplayLinkStop(_displayLink!)
                    } else {
                        CVDisplayLinkStart(_displayLink!)
                    }
                #endif
                
                
            }
        }
        
        get {
            return _gameLoopPaused
        }
    }
    
    @objc func didEnterBackground(_ notification: Notification) {
        self.paused = true
    }
    
    @objc func willEnterForeground(_ notification: Notification) {
        self.paused = false
    }
    
    #if os(iOS)
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // run the game loop
        self.dispatchGameLoop()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // end the gameloop
        self.stopGameLoop()
    }
    #endif
    
}
