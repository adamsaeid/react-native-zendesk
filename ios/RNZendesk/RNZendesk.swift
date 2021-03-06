//
//  RNZendesk.swift
//  RNZendesk
//
//  Created by David Chavez on 24.04.18.
//  Copyright © 2018 David Chavez. All rights reserved.
//

import UIKit
import Foundation
import ZendeskSDK
import ZendeskCoreSDK
import CommonUISDK

@objc(RNZendesk)
class RNZendesk: RCTEventEmitter {

    override public static func requiresMainQueueSetup() -> Bool {
        return false;
    }
    
    @objc(constantsToExport)
    override func constantsToExport() -> [AnyHashable: Any] {
        return [:]
    }
    
    @objc(supportedEvents)
    override func supportedEvents() -> [String] {
        return []
    }
    
    
    // MARK: - Initialization

    @objc(initialize:)
    func initialize(config: [String: Any]) {
        guard
            let appId = config["appId"] as? String,
            let clientId = config["clientId"] as? String,
            let zendeskUrl = config["zendeskUrl"] as? String else { return }
        
        Zendesk.initialize(appId: appId, clientId: clientId, zendeskUrl: zendeskUrl)
        Support.initialize(withZendesk: Zendesk.instance)
    }
    
    // MARK: - Indentification
    
    @objc(identifyJWT:)
    func identifyJWT(token: String?) {
        guard let token = token else { return }
        let identity = Identity.createJwt(token: token)
        Zendesk.instance?.setIdentity(identity)
    }
    
    @objc(identifyAnonymous:email:)
    func identifyAnonymous(name: String?, email: String?) {
        let identity = Identity.createAnonymous(name: name, email: email)
        Zendesk.instance?.setIdentity(identity)
    }
    
    // MARK: - Notifications

    @objc(registerWithDeviceIdentifier:successCallback:errorCallback:)
    func registerWithDeviceIdentifier(deviceIdentifier: String, successCallback: @escaping RCTResponseSenderBlock, errorCallback: @escaping RCTResponseSenderBlock) {
        let locale = NSLocale.preferredLanguages.first ?? "en"
        ZDKPushProvider(zendesk: Zendesk.instance!).register(deviceIdentifier: deviceIdentifier, locale: locale) { (pushResponse, error) in
            if(error != nil) {
                errorCallback(["\(error)"])
            } else {
                successCallback([pushResponse])
            }
        }
    }    

    @objc(unregisterDevice)
    func unregisterDevice() {
        ZDKPushProvider(zendesk: Zendesk.instance!).unregisterForPush()
    }

    // MARK: - UI Methods
    
    @objc(showHelpCenter:)
    func showHelpCenter(with options: [String: Any]) {
        DispatchQueue.main.async {
            let hcConfig = HelpCenterUiConfiguration()
            hcConfig.hideContactSupport = (options["hideContactSupport"] as? Bool) ?? false
            let helpCenter = HelpCenterUi.buildHelpCenterOverviewUi(withConfigs: [hcConfig])
            
            let nvc = UINavigationController(rootViewController: helpCenter)
            UIApplication.shared.keyWindow?.rootViewController?.present(nvc, animated: true, completion: nil)
        }
    }
    
    @objc(showNewTicket:)
    func showNewTicket(with options: [String: Any]) {
        DispatchQueue.main.async {
            let config = RequestUiConfiguration()
            if let tags = options["tags"] as? [String] {
                config.tags = tags
            }
            let requestScreen = RequestUi.buildRequestUi(with: [config])
            
            let nvc = UINavigationController(rootViewController: requestScreen)
            UIApplication.shared.keyWindow?.rootViewController?.present(nvc, animated: true, completion: nil)
        }
    }

    @objc(showTicket:)
    func showTicket(with requestId: String) {        
        DispatchQueue.main.async {
            let requestScreen = RequestUi.buildRequestUi(requestId: requestId)
            let nvc = UINavigationController(rootViewController: requestScreen)
            if var topController = UIApplication.shared.keyWindow?.rootViewController {
                while let presentedViewController = topController.presentedViewController {
                    topController = presentedViewController
                }

                topController.present(nvc, animated: true, completion: nil)
            }
        }
    }

    @objc(refreshTicket:resultCallback:)
    func refreshTicket(requestId: String, resultCallback: @escaping RCTResponseSenderBlock) {
        DispatchQueue.main.async {
            let ticketWasVisibleAndRefreshed = Support.instance?.refreshRequest(requestId: requestId)
            resultCallback([ticketWasVisibleAndRefreshed])
        }
    }

    @objc(showTicketList)
    func showTicketList() {
        DispatchQueue.main.async {
            let requestListController = RequestUi.buildRequestList()
            
            let nvc = UINavigationController(rootViewController: requestListController)
            UIApplication.shared.keyWindow?.rootViewController?.present(nvc, animated: true)
        }
    }

    // MARK: - Ticket Methods
    @objc(createTicket:desc:tags:attachments:resolve:reject:)
    func createTicket(with subject: String, desc: String, tags: Array<String>, attachments: Array<String>, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            let request = ZDKCreateRequest()
            request.subject = subject
            request.requestDescription = desc
            request.tags = tags
            
            attachments.forEach { attachment in
                var uploadResponse = ZDKUploadResponse()
                uploadResponse.uploadToken = attachment
                request.attachments.append(uploadResponse)
            }

            ZDKRequestProvider().createRequest(request) { (result, error) in
                // TODO resolve and reject in a meaningful way (iOS should match android on this)
                // if let result = result {
                if result != nil {
                    resolve("Create ticket result received")
                } else if let error = error {
                    reject("zendesk_error", error.localizedDescription, error);
                } else {
                    let unKnownError = NSError(domain: "", code: 200, userInfo: nil)
                    reject("unknown_error", "Unexpected error", unKnownError)
                }
            }
        }
    }

    @objc(uploadAttachment:mimeType:fileName:resolve:reject:)
    func uploadAttachment(path: String, mimeType: String, fileName: String, resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        DispatchQueue.main.async {
            let theProfileImageUrl = URL(string: "file://" + path)
            do {
                let attachment = try Data(contentsOf: theProfileImageUrl!)
                ZDKUploadProvider().uploadAttachment(attachment, withFilename: fileName, andContentType: mimeType) { (response, error) in
                    // TODO resolve and reject in a meaningful way (iOS should match android on this)
                    if let response = response {
                        resolve(response.uploadToken!)
                    } else if let error = error {
                        reject("zendesk_error", error.localizedDescription, error);
                    } else {
                        let unKnownError = NSError(domain: "", code: 200, userInfo: nil)
                        reject("unexpected_error", "Unexpected error", unKnownError)
                    }
                }
            } catch {
                print("Unable to load data: \(error)")
                reject("unknown_error", "Unknown error", error)
            }
        }
    }
}
