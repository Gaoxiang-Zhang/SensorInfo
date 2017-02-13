//
//  ViewController.swift
//  SensorInfo
//
//  Created by 张高翔 on 2016/12/3.
//  Copyright © 2016年 Gaoxiang Zhang. All rights reserved.
//

import UIKit
import CoreMotion
import AVFoundation
import SVProgressHUD

let AMAP_KEY = "f042636e714a6025f17193aca567652d";

class ViewController: UIViewController, AMapLocationManagerDelegate{
    
    // camera preview
    @IBOutlet weak var cameraPreviewView: UIView!
    
    // the item count of IMU
    @IBOutlet weak var imuCountLabel: UILabel!
    @IBOutlet weak var imageCountLabel: UILabel!
    @IBOutlet weak var gpsCountLabel: UILabel!
    
    // the count of the imu, image and gps
    var imuCount: Int = 0, imageCount: Int = 0, gpsCount: Int = 0
    
    // flag of tracking
    var isTracking: Bool = false
    
    // motion manager for acc and gyro
    var motionManager: CMMotionManager!
    // timer of scheduling the sensor reader
    var sensorTimer: Timer!
    // array of sensor readings: timestamp ax ay az wx wy wz
    var sensorReadings: [String] = [String]()
    
    // camera related
    var captureSession: AVCaptureSession?
    var stillImageOutput: AVCaptureStillImageOutput?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var cameraTimer: Timer!
    
    // locating services
    var locationManager: AMapLocationManager!
    var gpsReadings: [String] = [String]()
    
    // file I/O
    var currentFolder: URL!
    
    // some static parameters
    let SENSOR_TIME_INTERVAL: TimeInterval = 1 / 10
    let IMAGE_TIME_INTERVAL: Double = 1.0
    let SENSOR_FILE = "sensors.txt"
    let GPS_FILE = "gps.txt"
    let GPS_MIN_DISTANCE = 1

    override func viewDidLoad() {
        super.viewDidLoad()
        
        initCamera()
        initSensors()
        initLocating()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        locationManager.stopUpdatingLocation()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        previewLayer!.frame = cameraPreviewView.bounds
    }
    
    func initCamera(){
        // establish the capture session
        captureSession = AVCaptureSession()
        // set the resolution
        captureSession!.sessionPreset = AVCaptureSessionPreset640x480
        
        // set input
        let backCamera = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        var input: AVCaptureDeviceInput!
        var error: NSError?
        do{
            input = try AVCaptureDeviceInput(device: backCamera)
        } catch let error1 as NSError {
            error = error1
            input = nil
            return
        }
        
        // if there is no error of the input
        if error == nil && captureSession!.canAddInput(input){
            captureSession!.addInput(input)
            // set the output
            stillImageOutput = AVCaptureStillImageOutput()
            stillImageOutput!.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
            if captureSession!.canAddOutput(stillImageOutput){
                captureSession!.addOutput(stillImageOutput)
                previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
                previewLayer!.videoGravity = AVLayerVideoGravityResizeAspect
                previewLayer!.connection?.videoOrientation = AVCaptureVideoOrientation.landscapeRight
                cameraPreviewView.layer.addSublayer(previewLayer!)
                
                captureSession!.startRunning()
            }
        }
    }
    
    // initialize the motion sensor
    func initSensors(){
        motionManager = CMMotionManager()
        // start tracking of accelerometer and gyroscope
        motionManager.startGyroUpdates()
        motionManager.startAccelerometerUpdates()
        // set timer
        sensorTimer = Timer.scheduledTimer(timeInterval: SENSOR_TIME_INTERVAL, target: self, selector: #selector(ViewController.sensorUpdate), userInfo: nil, repeats: true)
    }
    
    // initialize the location service
    func initLocating(){
        AMapServices.shared().apiKey = AMAP_KEY
        // init
        locationManager = AMapLocationManager.init()
        locationManager.delegate = self
        // set min distance
        locationManager.distanceFilter = CLLocationDistance(GPS_MIN_DISTANCE)
        // no geo code
        locationManager.locatingWithReGeocode = false
        // start locating
        locationManager.startUpdatingLocation()
    }
    
    func setView(){
        imuCountLabel.text = String(imuCount)
        gpsCountLabel.text = String(gpsCount)
        imageCountLabel.text = String(imageCount)
    }
    
    // location update
    func amapLocationManager(_ manager: AMapLocationManager!, didUpdate location: CLLocation!) {
        let info = String(location.coordinate.latitude) + " " + String(location.coordinate.longitude)
        gpsReadings.append(info)
        //print(info)
        
        // update the view
        gpsCount += 1
        setView()
    }
    
    // get current timestamp
    func getCurrentTimestamp() -> Int{
        let now = NSDate()
        // the timeIntervalSince1970 is a double value represent the seconds
        let timeInterval:TimeInterval = now.timeIntervalSince1970 * 1000
        return Int(timeInterval)
    }
    
    // capture image
    func captureImage() {
        // the filename is defined by current timestamp
        let filename = getCurrentTimestamp()
        if let videoConnection = stillImageOutput!.connection(withMediaType: AVMediaTypeVideo){
            videoConnection.videoOrientation = AVCaptureVideoOrientation.landscapeRight
            stillImageOutput?.captureStillImageAsynchronously(from: videoConnection, completionHandler: {(sampleBuffer, error) in
                if (sampleBuffer != nil) {
                    let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sampleBuffer) as CFData
                    let dataProvider = CGDataProvider(data: imageData)!
                    let cgImageRef = CGImage(jpegDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: CGColorRenderingIntent.defaultIntent)
                    let image = UIImage(cgImage: cgImageRef!, scale: 1.0, orientation: UIImageOrientation.up)
                    self.saveImage(image: image, timestamp: filename)
                    
                    // update the view
                    self.imageCount += 1
                    self.setView()
                }
            })
        }
    }
    
    func captureContinuousImages(){
        cameraTimer = Timer.scheduledTimer(timeInterval: IMAGE_TIME_INTERVAL, target: self, selector: #selector(ViewController.captureImage), userInfo: nil, repeats: true)
    }
    
    // initialize the directory using in this tracking
    func initIO() {
        // initialize the folder
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsDirectory = paths[0]
        currentFolder = documentsDirectory.appendingPathComponent(getCurrentFolderName())
        do{
            try FileManager.default.createDirectory(at: currentFolder, withIntermediateDirectories: false, attributes: nil)
        } catch let error as NSError{
            print(error.localizedDescription)
        }
        // clear all of the flags and containers
        imuCount = 0
        imageCount = 0
        gpsCount = 0
        gpsReadings.removeAll()
        sensorReadings.removeAll()
    }
    
    // get the photo folder name by current hour and minute
    func getCurrentFolderName() -> String{
        let hour = Calendar.current.component(.hour, from: Date())
        let minute = Calendar.current.component(.minute, from: Date())
        return String(hour) + "_" + String(minute)
    }
    
    // save UIImage to the filesystem
    func saveImage(image: UIImage, timestamp: Int) {
        if let data = UIImageJPEGRepresentation(image, 0.8){
            let filename = currentFolder.appendingPathComponent(String(timestamp) + ".png")
            try? data.write(to: filename)
        }
    }
    
    // save the result of sensor/gps tracking results in the file
    func saveSensor(){
        DispatchQueue.global(qos: .background).async {
            let filename1 = self.currentFolder.appendingPathComponent(self.SENSOR_FILE)
            let filename2 = self.currentFolder.appendingPathComponent(self.GPS_FILE)
            do{
                let str1 = self.sensorReadings.joined(separator: "\n")
                try str1.write(to: filename1, atomically: false, encoding: String.Encoding.utf8)
                let str2 = self.gpsReadings.joined(separator: "\n")
                try str2.write(to: filename2, atomically: false, encoding: String.Encoding.utf8)
            } catch{
                print("Something wrong happened during the sensor writing process...")
            }
            DispatchQueue.main.async {
                SVProgressHUD.showInfo(withStatus: "Stop Tracking")
            }
        }
    }
    
    // callback of sensor updates
    func sensorUpdate(){
        if(!isTracking){
            return
        }
        var line = String(getCurrentTimestamp()).appending(" ")
        if let accelerometerData = motionManager.accelerometerData{
            line += String(accelerometerData.acceleration.x) + " "
            line += String(accelerometerData.acceleration.y) + " "
            line += String(accelerometerData.acceleration.z) + " "
        }
        if let gyroData = motionManager.gyroData{
            line += String(gyroData.rotationRate.x) + " "
            line += String(gyroData.rotationRate.y) + " "
            line += String(gyroData.rotationRate.z) + " "
        }
        //print(line)
        sensorReadings.append(line)
        
        // update the view
        imuCount += 1
        setView()
    }
    
    // press the start button to start tracking
    @IBAction func startTracking(_ sender: UIButton) {
        if(isTracking){
            return;
        }
        SVProgressHUD.showInfo(withStatus: "Start Tracking")
        initIO()
        isTracking = true
        captureContinuousImages()
    }
    
    // press the stop button to stop tracking
    @IBAction func stopTracking(_ sender: UIButton) {
        if(!isTracking){
            return;
        }
        isTracking = false
        cameraTimer.invalidate()
        cameraTimer = nil
        saveSensor()
    }
    
}

