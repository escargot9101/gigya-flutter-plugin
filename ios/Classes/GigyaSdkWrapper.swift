import Gigya
import GigyaAuth
/**
 Plugin specific error constants.
 */
public class PluginErrors {
    static let generalError = "700"
    static let generalErrorMessage = "general error"
    static let missingParameterError = "701"
    static let missingParameterMessage = "request parameter missing"
    static let unsupportedError = "702"
    static let unsupportedErrorMessage = "not supported in this iOS version"
}

public class GigyaSdkWrapper<T: GigyaAccountProtocol> :GigyaInstanceProtocol {
    
    let sdk: GigyaCore<T>?
    
    let resolverHelper: ResolverHelper<T> = ResolverHelper()
    
    init(accountSchema: T.Type) {
        // Initializing the Gigya SDK instance.
        GigyaDefinitions.versionPrefix = "flutter_0.3.0_"
        sdk = Gigya.sharedInstance(accountSchema)
        GigyaAuth.shared.register(scheme: accountSchema)
    }
    
    // MARK: - Main instance
    
    /**
     Send general/anonymous request
     */
    func sendRequest(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let endpoint = arguments["endpoint"] as? String,
              let parameters = arguments["parameters"] as? [String:Any] else {
            result(FlutterError(code: PluginErrors.missingParameterError, message: PluginErrors.missingParameterMessage, details: nil))
            return
        }
        
        sdk?.send(api: endpoint, params: parameters) { (gigyaResponse) in
            switch gigyaResponse {
            case .success(let data):
                let json = data.mapValues { $0.value }.asJson
                result(json)
            case .failure(let error):
                switch error {
                case .gigyaError(let ge):
                    result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                default:
                    result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                }
            }
        }
    }
    
    /**
     Login using credentials (loginId/password combination with optional parameter map).
     */
    func loginWithCredentials(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let loginId = arguments["loginId"] as? String,
              let password = arguments["password"] as? String else {
            result(FlutterError(code: PluginErrors.missingParameterError, message: PluginErrors.missingParameterMessage, details: nil))
            return
        }
        
        let parameters = arguments["parameters"] as? [String: Any] ?? [:]
        sdk?.login(loginId: loginId, password: password, params: parameters) { [weak self] loginResult in
            switch loginResult {
            case .success(let data):
                self?.resolverHelper.dispose()

                result(self?.mapObject(data))
            case .failure(let error):
                self?.saveResolvesIfNeeded(interruption: error.interruption)
                
                switch error.error {
                case .gigyaError(let ge):
                    result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                default:
                    result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                }
            }
        }
    }
    
    /**
     Register a new user using credentials (email/password combination with optional parameter map).
     */
    func registerWithCredentials(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let email = arguments["email"] as? String,
              let password = arguments["password"] as? String else {
            result(FlutterError(code: PluginErrors.missingParameterError, message: PluginErrors.missingParameterMessage, details: nil))
            return
        }
        
        let parameters = arguments["parameters"] as? [String: Any] ?? [:]
        sdk?.register(email: email, password: password, params: parameters) { [weak self] loginResult in
            switch loginResult {
            case .success(let data):
                self?.resolverHelper.dispose()

                result(self?.mapObject(data))
            case .failure(let error):
                self?.saveResolvesIfNeeded(interruption: error.interruption)
                
                switch error.error {
                case .gigyaError(let ge):
                    result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                default:
                    result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                }
            }
        }
    }
    
    /**
     Check login status.
     */
    func isLoggedIn(result: @escaping FlutterResult) {
        result(sdk?.isLoggedIn() ?? false)
    }
    
    /**
     Request active account.
     */
    func getAccount(arguments: [String: Any], result: @escaping FlutterResult) {
        let clearCache = arguments["invalidate"] as? Bool ?? false
        let parameters = arguments["parameters"] as? [String: Any] ?? [:]
        sdk?.getAccount(clearCache, params: parameters) { [weak self] accountResult in
            switch accountResult {
            case .success(let data):
                let mapped = self?.mapObject(data)
                result(mapped)
            case .failure(let error):
                switch error {
                case .gigyaError(let ge):
                    result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                default:
                    result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                }
            }
        }
    }
    
    /**
     Update account information
     */
    func setAccount(arguments: [String: Any], result: @escaping FlutterResult) {
        let account = arguments["account"] as? [String: Any] ?? [:]
        sdk?.setAccount(with: account, completion: { [weak self] accountResult in
            switch accountResult {
            case .success(let data):
                let mapped = self?.mapObject(data)
                result(mapped)
            case .failure(let error):
                switch error {
                case .gigyaError(let ge):
                    result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                default:
                    result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                }
            }
        })
    }
    
    /**
     Get current session
     */
    func getSession(result: @escaping FlutterResult) {
        let session = sdk?.getSession()
        if (session != nil) {
            // The timestamp is a Double? but the `expires_in` is expected to be an Int? so convert it.
            let sessionExpirationTimestamp : Double? = session?.sessionExpirationTimestamp

            var timestamp: Int? = nil

            if (sessionExpirationTimestamp != nil) {
                timestamp = Int(sessionExpirationTimestamp!)
            }

            result(["sessionToken": session?.token, "sessionSecret": session?.secret, "expires_in": timestamp])
        } else {
            result(nil)
        }
    }
    
    /**
     Override exists session
     */
    func setSession(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let token = arguments["sessionToken"] as? String,
              let secret = arguments["sessionSecret"] as? String,
              let expiration = arguments["expires_in"] as? Int else {
            result(FlutterError(code: PluginErrors.missingParameterError, message: PluginErrors.missingParameterMessage, details: nil))
            return
        }

        // `expiration` is an Int but a Double is expected by the SDK, so convert it.
        let newSession = GigyaSession(sessionToken: token, secret: secret, expiration: Double(expiration))
        sdk?.setSession(newSession!)
        
        result(nil)
    }
    
    /**
     Logout of existing session.
     */
    func logOut(result: @escaping FlutterResult) {
        let isLoggedIn = sdk?.isLoggedIn() ?? false

        if(!isLoggedIn) {
            result(nil)

            return
        }

        sdk?.logout(completion: { gigyaResponse in
            switch gigyaResponse {
            case .success( _):
                result(nil)
            case .failure(let error):
                switch error {
                case .gigyaError(let d):
                    result(FlutterError(code: "\(d.errorCode)", message: d.errorMessage, details: d.toDictionary()))
                default:
                    result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                }
            }
        })
    }
    
    /**
     Forgot password
     */
    func forgotPassword(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let loginId = arguments["loginId"] as? String else {
            result(FlutterError(code: PluginErrors.missingParameterError, message: PluginErrors.missingParameterMessage, details: nil))
            return
        }
        sdk?.forgotPassword(loginId: loginId, completion: { [weak self] gigyaResponse in
            switch gigyaResponse {
            case .success(let data):
                let mapped = self?.mapObject(data)
                result(mapped)
            case .failure(let error):
                switch error {
                case .gigyaError(let d):
                    result(FlutterError(code: "\(d.errorCode)", message: d.errorMessage, details: d.toDictionary()))
                default:
                    result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                }
            }
        })
    }

    /**
     Init SDK
     */
    func initSdk(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let apiKey = arguments["apiKey"] as? String,
              let apiDomain = arguments["apiDomain"] as? String else {
            result(FlutterError(code: PluginErrors.missingParameterError, message: PluginErrors.missingParameterMessage, details: nil))
            return
        }
        sdk?.initFor(apiKey: apiKey, apiDomain: apiDomain)
        
        result(nil)
    }
    
    /**
     Social login with given provider & provider sessions.
     */
    func socialLogin(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let viewController = getDisplayedViewController()
        else {
            result(FlutterError(code: PluginErrors.generalError, message: "view controller not available", details: nil))
            return
        }

        guard let providerString = arguments["provider"] as? String 
        else {
            result(FlutterError(code: PluginErrors.missingParameterError, message: PluginErrors.missingParameterMessage, details: nil))
            return
        }

        guard let provider = GigyaSocialProviders(rawValue: providerString)
        else {
            result(FlutterError(code: PluginErrors.generalError, message: "provider does not exist", details: nil))
            return
        }
        
        let parameters = arguments["parameters"] as? [String: Any] ?? [:]
        
        sdk?.login(
            with: provider,
            viewController: viewController,
            params: parameters) { [weak self] (gigyaResponse) in
                switch gigyaResponse {
                case .success(let data):
                    let mapped = self?.mapObject(data)
                    self?.resolverHelper.dispose()

                    result(mapped)
                case .failure(let error):
                    self?.saveResolvesIfNeeded(interruption: error.interruption)
                    
                    switch error.error {
                    case .gigyaError(let ge):
                        result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                    default:
                        result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                    }
                }
            }
    }
    
    /**
     SSO.
     */
    func sso(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let viewController = getDisplayedViewController()
        else {
            result(FlutterError(code: PluginErrors.generalError, message: "view controller not available", details: nil))
            return
        }
        
        let parameters = arguments["parameters"] as? [String: Any] ?? [:]
        
        sdk?.login(
            with: .sso,
            viewController: viewController,
            params: parameters) { [weak self] (gigyaResponse) in
                switch gigyaResponse {
                case .success(let data):
                    
                    let mapped = self?.mapObject(data)
                    self?.resolverHelper.dispose()

                    result(mapped)
                case .failure(let error):
                    self?.saveResolvesIfNeeded(interruption: error.interruption)
                    
                    switch error.error {
                    case .gigyaError(let ge):
                        result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                    default:
                        result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                    }
                }
            }
    }
    
    func addConnection(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let viewController = getDisplayedViewController()
        else {
            result(FlutterError(code: PluginErrors.generalError, message: "view controller not available", details: nil))
            return
        }

        guard let providerString = arguments["provider"] as? String 
        else {
            result(FlutterError(code: PluginErrors.missingParameterError, message: PluginErrors.missingParameterMessage, details: nil))
            return
        }

        guard let provider = GigyaSocialProviders(rawValue: providerString)
        else {
            result(FlutterError(code: PluginErrors.generalError, message: "provider does not exist", details: nil))
            return
        }
        
        let parameters = arguments["parameters"] as? [String: Any] ?? [:]
        
        sdk?.addConnection(
            provider: provider,
            viewController: viewController,
            params: parameters) { [weak self] gigyaResponse in
                switch gigyaResponse {
                case .success(let data):
                    let mapped = self?.mapObject(data)
                    result(mapped)
                case .failure(let error):
                    switch error {
                    case .gigyaError(let ge):
                        result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                    default:
                        result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                    }
                }
            }
    }
    
    func removeConnection(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let providerString = arguments["provider"] as? String 
        else {
            result(FlutterError(code: PluginErrors.missingParameterError, message: PluginErrors.missingParameterMessage, details: nil))
            return
        }

        guard let provider = GigyaSocialProviders(rawValue: providerString)
        else {
            result(FlutterError(code: PluginErrors.generalError, message: "provider does not exist", details: nil))
            return
        }
        
        sdk?.removeConnection(provider: provider) { gigyaResponse in
            switch gigyaResponse {
            case .success(let data):
                let returnData = data.mapValues { $0.value }
                result(returnData)
            case .failure(let error):
                switch error {
                case .gigyaError(let ge):
                    result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                default:
                    result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                }
            }
        }
    }
    
    /**
     Show screensets.
     */
    func showScreenSet(arguments: [String: Any], result: @escaping FlutterResult, handler: ScreenSetEventDelegate) {
        guard let viewController = getDisplayedViewController()
        else {
            result(FlutterError(code: PluginErrors.generalError, message: "view controller not available", details: nil))
            return
        }

        guard let screenSet = arguments["screenSet"] as? String 
        else {
            result(FlutterError(code: PluginErrors.missingParameterError, message: PluginErrors.missingParameterMessage, details: nil))
            return
        }
        
        let parameters = arguments["parameters"] as? [String: Any] ?? [:]
        
        //TODO missing onAfterValidation in SDK.
        sdk?.showScreenSet(
            with: screenSet,
            viewController: viewController,
            params: parameters) { [weak self] event in
                switch event {
                case .error(let event):
                    handler.addScreenSetEvent(event: ["event":"onError", "data" : event])
                case .onHide(let event):
                    handler.addScreenSetEvent(event: ["event":"onHide", "data" : event])
                case .onLogin(account: let account):
                    handler.addScreenSetEvent(event: ["event":"onLogin", "data" : self?.mapObject(account) ?? [:]])
                case .onLogout:
                    handler.addScreenSetEvent(event: ["event":"onLogout"])
                case .onConnectionAdded:
                    handler.addScreenSetEvent(event: ["event":"onConnectionAdded"])
                case .onConnectionRemoved:
                    handler.addScreenSetEvent(event: ["event":"onConnectionRemoved"])
                case .onBeforeScreenLoad(let event):
                    handler.addScreenSetEvent(event: ["event":"onBeforeScreenLoad", "data" : event])
                case .onAfterScreenLoad(let event):
                    handler.addScreenSetEvent(event: ["event":"onAfterScreenLoad", "data" : event])
                case .onBeforeValidation(let event):
                    handler.addScreenSetEvent(event: ["event":"onBeforeValidation", "data" : event])
                case .onAfterValidation(let event):
                    handler.addScreenSetEvent(event: ["event":"onAfterValidation", "data" : event])
                case .onBeforeSubmit(let event):
                    handler.addScreenSetEvent(event: ["event":"onBeforeSubmit", "data" : event])
                case .onSubmit(let event):
                    handler.addScreenSetEvent(event: ["event":"onSubmit", "data" : event])
                case .onAfterSubmit(let event):
                    handler.addScreenSetEvent(event: ["event":"onAfterSubmit", "data" : event])
                case .onFieldChanged(let event):
                    handler.addScreenSetEvent(event: ["event":"onFieldChanged", "data" : event])
                case .onCanceled:
                    handler.addScreenSetEvent(event: ["event": "onCancel", "data": ["errorCode" : "200001", "errorMessage":"Operation canceled"]])
                }
            }

        result(nil)
    }
    
    func webAuthnLogin(result: @escaping FlutterResult) {
        guard let viewController = getDisplayedViewController()
        else {
            result(FlutterError(code: PluginErrors.generalError, message: "view controller not available", details: nil))
            return
        }
        
        if #available(iOS 16.0.0, *) {            
            Task { [weak self] in
                guard let loginResult = await sdk?.webAuthn.login(viewController: viewController)
                else {
                    result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                    return
                }
                
                switch loginResult {
                case .success(let data):
                    let mapped = self?.mapObject(data)
                    self?.resolverHelper.dispose()

                    result(mapped)                    
                case .failure(let error):
                    self?.saveResolvesIfNeeded(interruption: error.interruption)
                    
                    switch error.error {
                    case .gigyaError(let ge):
                        result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                    default:
                        result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                    }
                }
            }
        } else {
            result(FlutterError(code: PluginErrors.unsupportedError, message: PluginErrors.unsupportedErrorMessage, details: nil))
        }
    }
    
    func webAuthnRegister(result: @escaping FlutterResult) {
        guard let viewController = getDisplayedViewController()
        else {
            result(FlutterError(code: PluginErrors.generalError, message: "view controller not available", details: nil))
            return
        }
        
        if #available(iOS 16.0.0, *) {
            Task {
                guard let registerResult = await sdk?.webAuthn.register(viewController: viewController) 
                else {
                    result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                    return
                }
                
                switch registerResult {
                case .success(let data):
                    let json = data.mapValues { $0.value }.asJson
                    result(json)
                case .failure(let error):
                    switch error {
                    case .gigyaError(let ge):
                        result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                    default:
                        result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                    }
                }
            }
        } else {
            result(FlutterError(code: PluginErrors.unsupportedError, message: PluginErrors.unsupportedErrorMessage, details: nil))
        }
    }
    
    func webAuthnRevoke(result: @escaping FlutterResult) {
        if #available(iOS 16.0.0, *) {
            Task {
                guard let revokeResult = await sdk?.webAuthn.revoke() 
                else {
                    result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                    return
                }
                
                switch revokeResult {
                case .success(let data):
                    let json = data.mapValues { $0.value }.asJson
                    result(json)
                case .failure(let error):
                    switch error {
                    case .gigyaError(let ge):
                        result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                    default:
                        result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                    }
                }
            }
        } else {
            result(FlutterError(code: PluginErrors.unsupportedError, message: PluginErrors.unsupportedErrorMessage, details: nil))
        }
    }
}

// MARK: - Resolvers
extension GigyaSdkWrapper {
    /**
     Link account - handler for fetching conflicting accounts from current interruption state.
     */
    func resolveGetConflictingAccounts(result: @escaping FlutterResult) {
        guard let resolver = resolverHelper.linkAccountResolver else {
            result(FlutterError(code: PluginErrors.generalError, message: "resolver not found", details: nil))
            
            return
        }
        
        result(mapObject(resolver.conflictingAccount!))
    }
    
    /**
     Link account - resolving link to site.
     */
    func resolveLinkToSite(arguments: [String: Any], result: @escaping FlutterResult) {        
        guard let resolver = resolverHelper.linkAccountResolver else {
            result(FlutterError(code: PluginErrors.generalError, message: "resolver not found", details: nil))
            
            return
        }
        
        guard
            let loginId = arguments["loginId"] as? String,
            let password = arguments["password"] as? String else {
                result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                return
            }
        
        resolver.linkToSite(loginId: loginId, password: password)

        result(nil)
    }
    
    /**
     Link account - resolving link to social.
     */
    func resolveLinkToSocial(arguments: [String: Any], result: @escaping FlutterResult) {        
        guard let resolver = resolverHelper.linkAccountResolver else {
            result(FlutterError(code: PluginErrors.generalError, message: "resolver not found", details: nil))
            
            return
        }
        
        guard let viewController = getDisplayedViewController(),
              let providerString = arguments["provider"] as? String,
              let provider = GigyaSocialProviders(rawValue: providerString)
        else {
            result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
            return
        }
        
        resolver.linkToSocial(provider: provider, viewController: viewController)

        result(nil)
    }
    
    /**
     Pending registration - resolving missing account data.
     */
    func resolveSetAccount(arguments: [String: Any], result: @escaping FlutterResult) {        
        guard let resolver = resolverHelper.pendingRegistrationResolver else {
            result(FlutterError(code: PluginErrors.generalError, message: "resolver not found", details: nil))
            
            return
        }
        
        resolver.setAccount(params: arguments)

        result(nil)
    }

}

// MARK: - Otp
extension GigyaSdkWrapper {

    /**
     Login using credentials (loginId/password combination with optional parameter map).
     */
    func otpLogin(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let phone = arguments["phone"] as? String else {
            result(FlutterError(code: PluginErrors.missingParameterError, message: PluginErrors.missingParameterMessage, details: nil))
            return
        }

        let parameters = arguments["parameters"] as? [String: Any] ?? [:]
        GigyaAuth.shared.otp.login(phone: phone, params: parameters ) { (loginResult: GigyaOtpResult<T>) in
            switch loginResult {
            case .success(let data):
                let mapped = self.mapObject(data)
                self.resolverHelper.dispose()
                result(mapped)
            case .failure(let error):
                self.saveResolvesIfNeeded(interruption: error.interruption)

                switch error.error {
                case .gigyaError(let ge):
                    result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                default:
                    result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                }
            case .pendingOtpVerification(resolver: let resolver):
                self.resolverHelper.pendingOtpResolver = resolver
                let data = resolver.data?.mapValues { value in ((value as? AnyCodable) ?? AnyCodable.init("")).value }
                                
                result(data)
            }
        }
    }

   /**
     Login using credentials (loginId/password combination with optional parameter map).
     */
    func otpUpdate(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let phone = arguments["phone"] as? String else {
            result(FlutterError(code: PluginErrors.missingParameterError, message: PluginErrors.missingParameterMessage, details: nil))
            return
        }

        let parameters = arguments["parameters"] as? [String: Any] ?? [:]
        GigyaAuth.shared.otp.update(phone: phone, params: parameters ) { (loginResult: GigyaOtpResult<T>) in
            switch loginResult {
            case .success(let data):
                let mapped = self.mapObject(data)
                self.resolverHelper.dispose()
                result(mapped)
            case .failure(let error):
                self.saveResolvesIfNeeded(interruption: error.interruption)

                switch error.error {
                case .gigyaError(let ge):
                    result(FlutterError(code: "\(ge.errorCode)", message: ge.errorMessage, details: ge.toDictionary()))
                default:
                    result(FlutterError(code: PluginErrors.generalError, message: PluginErrors.generalErrorMessage, details: nil))
                }
            case .pendingOtpVerification(resolver: let resolver):
                self.resolverHelper.pendingOtpResolver = resolver

                let data = resolver.data?.mapValues { value in ((value as? AnyCodable) ?? AnyCodable.init("")).value }
                                
                result(data)
            }
        }
    }

    func verifyOtp(arguments: [String: Any], result: @escaping FlutterResult) {
        guard let code = arguments["code"] as? String,
              let resolver = resolverHelper.pendingOtpResolver
        else {
            result(FlutterError(code: PluginErrors.missingParameterError, message: PluginErrors.missingParameterMessage, details: nil))
            return
        }
        
        resolver.verify(code: code)

        result(nil)
    }
}

class ResolverHelper<T: GigyaAccountProtocol> {    
    var linkAccountResolver: LinkAccountsResolver<T>?
    
    var pendingRegistrationResolver: PendingRegistrationResolver<T>?
    
    var pendingOtpResolver: OtpServiceVerifyProtocol?

    var regToken: String?
    
    func dispose() {
        linkAccountResolver = nil
        pendingRegistrationResolver = nil
        pendingOtpResolver = nil
        regToken = nil
    }
}
