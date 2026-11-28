package com.eyeswatchinggames.no_tide_back

import android.app.Activity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity for No Tide Back.
 *
 * Package, MethodChannel name and Xsolla credentials must never change:
 *   package      : com.eyeswatchinggames.no_tide_back
 *   channel      : com.eyeswatchinggames.no_tide_back/xsolla
 *   Xsolla login : 49611eb4-b8eb-4b52-95b6-0d0529436a0e
 *   Xsolla proj  : 322198
 *
 * ---------------------------------------------------------------------------
 * Which Xsolla SDK this targets
 * ---------------------------------------------------------------------------
 * Xsolla retired the old `login` / `payments` / `store` 3.1.0 artifacts (the
 * Gradle error "Could not find com.xsolla.android:store:3.1.0" is that
 * retirement, not a repo misconfiguration). The current SDK is a single
 * artifact that mirrors the Google Play Billing API:
 *
 *   com.xsolla.android:mobile:<version>
 *   maven { url "https://raw.githubusercontent.com/xsolla/xsolla-sdk-android/main" }
 *
 * It talks to Xsolla Pay Station, which also fronts Google Play purchases, so
 * this one rail covers the store without a second billing integration.
 *
 * The SDK is an *optional* dependency (build flag `-PwithXsolla`). Play /
 * Amazon / Samsung builds do not bundle it, so every call below is reflective:
 * this file compiles and runs against a classpath that does not contain it.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.eyeswatchinggames.no_tide_back/xsolla"

        /// Matches StoreChannel._channel in lib/services/store_channel.dart.
        const val STORE_CHANNEL = "com.eyeswatchinggames.no_tide_back/store"

        // ------------------------------------------------------------------
        // Xsolla credentials — do not alter.
        // ------------------------------------------------------------------
        const val XSOLLA_PROJECT_ID = 322198
        const val XSOLLA_LOGIN_ID = "49611eb4-b8eb-4b52-95b6-0d0529436a0e"

        const val SDK_PACKAGE = "com.xsolla.android.mobile"
        const val DESCRIPTOR = "com.xsolla.android.mobile."

        /// Shown verbatim by the store sheet when the AAR is not on the
        /// classpath (Play / Amazon / Samsung builds). Never a silent failure.
        const val NOT_BUNDLED =
            "This build has no Xsolla SDK bundled. Rebuild with -PwithXsolla " +
                "(the release workflows do this for the xsolla flavor)."
    }

    private var pendingSku: String? = null
    private var pendingResult: MethodChannel.Result? = null
    private var billingClient: Any? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initXsolla" -> connect { ok, error ->
                        if (ok) result.success(true) else result.error("XSOLLA_INIT", error, null)
                    }
                    // Diagnostic: asks the SDK for the SKU as each catalogue type
                    // and returns what it said. Lets the store sheet show the
                    // server's own answer instead of a guess.
                    "probeSku" -> {
                        val sku = call.argument<String>("sku")
                        if (sku.isNullOrBlank()) {
                            result.error("BAD_ARGS", "probeSku requires a sku", null)
                        } else {
                            probe(sku, result)
                        }
                    }
                    "buySku" -> {
                        val sku = call.argument<String>("sku")
                        if (sku.isNullOrBlank()) {
                            result.error("BAD_ARGS", "buySku requires a non-empty sku", null)
                        } else {
                            purchase(sku, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Install source: which store this APK came from. RevenueCat needs the
        // matching project key, and the compiled rail cannot know whether the
        // user installed from Play, Galaxy, or Amazon.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "installerPackage" -> result.success(installerPackage())
                    else -> result.notImplemented()
                }
            }
    }

    /// `com.android.vending`, `com.amazon.venezia`, `com.sec.android.app.samsungapps`,
    /// or null for a sideload (a null name here is normal, not an error).
    private fun installerPackage(): String? = try {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            packageManager.getInstallSourceInfo(packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstallerPackageName(packageName)
        }
    } catch (e: Exception) {
        android.util.Log.w("StoreChannel", "installerPackage unavailable", e)
        null
    }

    // ------------------------------------------------------------------------
    // Bridge helpers
    // ------------------------------------------------------------------------
    private fun sdkClass(simpleName: String): Class<*> = Class.forName(DESCRIPTOR + simpleName)

    /// `ProjectId.parse()` / `LoginUuid.parse()` return an Either; unwrap the
    /// right side (a malformed credential throws, which surfaces as XSOLLA_INIT).
    private fun unwrap(either: Any?): Any {
        requireNotNull(either) { "Xsolla SDK returned no value for a credential" }
        return either.javaClass.getMethod("getRightOrThrow").invoke(either)
    }

    private fun isSdkBundled(): Boolean = try {
        Class.forName(DESCRIPTOR + "BillingClient")
        true
    } catch (_: ClassNotFoundException) {
        false
    }

    /**
     * Creates the BillingClient with auto-JWT authentication for
     * Project 322198 / Login 49611eb4-…, then starts the connection.
     *
     * Mirrors the SDK's documented Kotlin usage:
     *   Config(Config.Common.getDefault(), Config.Integration.forXsolla(
     *     Config.Integration.Xsolla.Authentication.forAutoJWT(projectId, loginId)),
     *     Config.Payments.getDefault(), Config.Analytics.getDefault())
     */
    private fun connect(callback: (Boolean, String?) -> Unit) {
        if (!isSdkBundled()) {
            callback(false, NOT_BUNDLED)
            return
        }
        try {
            val commonClass = sdkClass("ConfigWithoutIntegration\$Common")
            val paymentsClass = sdkClass("ConfigWithoutIntegration\$Payments")
            val analyticsClass = sdkClass("ConfigWithoutIntegration\$Analytics")
            val integrationClass = sdkClass("Config\$Integration")
            val authClass = sdkClass("Config\$Integration\$Xsolla\$Authentication")
            val configClass = sdkClass("Config")
            val projectIdClass = sdkClass("ProjectId")
            val loginUuidClass = sdkClass("LoginUuid")
            val billingClientClass = sdkClass("BillingClient")
            val stateListenerClass = sdkClass("BillingClientStateListener")
            val updatedListenerClass = sdkClass("PurchasesUpdatedListener")

            // The store front sells coin packs as *virtual currency packages*
            // (a bundle) and the pack as a *virtual item*. Requested as plain
            // "inapp", the SDK rejects that type mismatch and
            // queryProductDetailsAsync answers OK with an EMPTY list — which
            // looks exactly like a missing catalogue entry. These two flags
            // (both default false) make those SKUs resolve as inapp.
            val common = commonClass.getMethod("getDefault").invoke(null)
                .let { base ->
                    try {
                        commonClass.getMethod(
                            "withAllowVirtualCurrencyAsInApp",
                            Boolean::class.javaPrimitiveType,
                        ).invoke(base, true)
                    } catch (_: NoSuchMethodException) {
                        base // older SDK
                    }
                }
                .let { base ->
                    try {
                        commonClass.getMethod(
                            "withAllowBundlesAsInApp",
                            Boolean::class.javaPrimitiveType,
                        ).invoke(base, true)
                    } catch (_: NoSuchMethodException) {
                        base
                    }
                }
            val payments = paymentsClass.getMethod("getDefault").invoke(null)
            val analytics = analyticsClass.getMethod("getDefault").invoke(null)

            // ProjectId.parse(int) / LoginUuid.parse(String) return Either;
            // getRightOrThrow() unwraps them (an invalid credential throws here,
            // which surfaces to Dart as XSOLLA_INIT instead of a silent hang).
            val projectId = unwrap(
                projectIdClass.getMethod("parse", Int::class.javaPrimitiveType)
                    .invoke(null, XSOLLA_PROJECT_ID),
            )
            val loginUuid = unwrap(
                loginUuidClass.getMethod("parse", String::class.java)
                    .invoke(null, XSOLLA_LOGIN_ID),
            )

            // `Config.Integration.forXsolla(...)` exists in 3.1.4 but is a
            // Kotlin inline/companion helper, so it is not reliably reachable
            // by reflection. The value it builds is
            // `Config.Integration.Xsolla(authentication, events)`, and its
            // constructor is public — build that directly.
            val auth = authClass
                .getMethod("forAutoJWT", projectIdClass, loginUuidClass)
                .invoke(null, projectId, loginUuid)
            val xsollaClass = sdkClass("Config\$Integration\$Xsolla")
            val integration = try {
                // Preferred: the documented factory, when reflection can see it.
                integrationClass
                    .getMethod("forXsolla", authClass)
                    .invoke(null, auth)
            } catch (_: NoSuchMethodException) {
                // No `Events.getDefault()` in this build: go through its Builder.
                val eventsClass = sdkClass("Config\$Integration\$Xsolla\$Events")
                val eventsBuilderClass = sdkClass("Config\$Integration\$Xsolla\$Events\$Builder")
                val events = eventsBuilderClass.getConstructor().newInstance().let { b ->
                    eventsBuilderClass.getMethod("build").invoke(b)
                }
                xsollaClass
                    .getDeclaredConstructors()
                    .firstOrNull { it.parameterTypes.size == 2 }
                    ?.also { it.isAccessible = true }
                    ?.newInstance(auth, events)
                    ?: throw IllegalStateException(
                        "Xsolla integration could not be constructed for this SDK build",
                    )
            }

            val config = configClass
                .getConstructor(commonClass, integrationClass, paymentsClass, analyticsClass)
                .newInstance(common, integration, payments, analytics)

            val updatesListener = java.lang.reflect.Proxy.newProxyInstance(
                classLoader,
                arrayOf(updatedListenerClass),
            ) { _, method, args ->
                if (method.name == "onPurchasesUpdated") handlePurchasesUpdated(args)
                null
            }

            val builder = billingClientClass.getMethod("newBuilder", android.content.Context::class.java)
                .invoke(null, applicationContext)
            builder.javaClass.getMethod("setListener", updatedListenerClass)
                .invoke(builder, updatesListener)
            builder.javaClass.getMethod("setConfig", configClass).invoke(builder, config)
            val client = builder.javaClass.getMethod("build").invoke(builder)
            billingClient = client

            val stateListener = java.lang.reflect.Proxy.newProxyInstance(
                classLoader,
                arrayOf(stateListenerClass),
            ) { _, method, args ->
                if (method.name == "onBillingSetupFinished") {
                    // `startConnection` reports its own failure here; treating
                    // every callback as success used to hide a bad project id or
                    // missing network behind a confusing "no product" error.
                    val result = args?.getOrNull(0)
                    val code = result?.javaClass?.getMethod("getResponseCode")
                        ?.invoke(result) as? Int ?: -1
                    if (code == 0) {
                        callback(true, null)
                    } else {
                        val detail = result?.javaClass?.getMethod("getDebugMessage")
                            ?.invoke(result) as? String
                        callback(
                            false,
                            detail ?: "Xsolla could not connect (code $code). " +
                                "Check the project id, the login id and the network.",
                        )
                    }
                }
                null
            }
            billingClientClass.getMethod("startConnection", stateListenerClass)
                .invoke(client, stateListener)
        } catch (e: ClassNotFoundException) {
            callback(false, NOT_BUNDLED)
        } catch (e: Throwable) {
            // Reflection against a moved SDK throws NoSuchMethod/IllegalAccess;
            // name the class so a version bump is obvious in logcat.
            android.util.Log.e("XsollaBridge", "connect failed", e)
            callback(
                false,
                e.cause?.message ?: e.message
                    ?: "${e.javaClass.simpleName} while starting the Xsolla client",
            )
        }
    }

    /**
     * Two-step purchase: resolve the ProductDetails for the SKU, then launch the
     * Pay Station flow. Entitlement is granted by Firestore only after the
     * purchase listener fires, never here.
     */
    private fun purchase(sku: String, result: MethodChannel.Result) {
        val client = billingClient
        if (client == null) {
            connect { ok, error ->
                if (!ok) {
                    result.error("XSOLLA_INIT", error, null)
                } else {
                    purchase(sku, result)
                }
            }
            return
        }
        if (pendingResult != null) {
            result.error("XSOLLA_BUSY", "A purchase is already in progress", null)
            return
        }
        pendingSku = sku
        pendingResult = result
        try {
            val billingClientClass = sdkClass("BillingClient")

            // Watchdog: a dead network used to leave the Dart side awaiting a
            // result forever, which disabled every BUY button in the sheet.
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(
                {
                    if (pendingSku == sku) {
                        failPending(
                            "XSOLLA_TIMEOUT",
                            "Pay Station did not answer within 25 s. Check the connection and retry.",
                        )
                    }
                },
                25_000,
            )

            // Ask for the SKU as an ordinary one-time product first, then fall
            // back to the other catalogue types. A coin pack is sold as a
            // *virtual currency package* (a bundle) and the pack as a *virtual
            // item*; requested as "inapp" without the matching Common flag the
            // SDK rejects the type mismatch with an EMPTY list, which is
            // indistinguishable from "no such product".
            // The SDK maps catalogue types as VIRTUAL_GOOD -> "inapp",
            // BUNDLE -> "bundle", VIRTUAL_CURRENCY -> "virtual_currency", and
            // rejects a mismatch with `Requested product is not available as the
            // requested type`. Try each one and keep what the server said, so a
            // failure can name the real reason instead of guessing.
            val attempts = mutableListOf<String>()
            fun tryType(index: Int) {
                val types = listOf("inapp", "bundle", "virtual_currency")
                if (index >= types.size) {
                    failSkuUnavailable(sku, attempts)
                    return
                }
                queryByType(client, sku, types[index]) { product, note ->
                    if (note != null) attempts.add("${types[index]}: $note")
                    if (product != null) launchFlow(product) else tryType(index + 1)
                }
            }
            tryType(0)
        } catch (e: Throwable) {
            android.util.Log.e("XsollaBridge", "queryProductDetails failed", e)
            // A NoSuchMethodException's message is just the class name, which is
            // useless to a player. Name the bridge as the culprit and keep the
            // SDK detail in logcat.
            val detail = e.message ?: e.javaClass.simpleName
            failPending(
                "XSOLLA_QUERY",
                if (e is NoSuchMethodException) {
                    "The Xsolla bridge does not match the bundled SDK version " +
                        "($detail). This is an app build issue, not your account — " +
                        "report it with this line."
                } else {
                    "Could not load the Xsolla catalog: $detail"
                },
            )
        }
    }

    /// Runs the catalogue query for [sku] as each type and reports the outcome.
    private fun probe(sku: String, result: MethodChannel.Result) {
        val client = billingClient
        if (client == null) {
            connect { ok, error ->
                if (!ok) {
                    result.error("XSOLLA_INIT", error, null)
                } else {
                    probe(sku, result)
                }
            }
            return
        }
        val report = mutableMapOf<String, String>()
        val types = listOf("inapp", "bundle", "virtual_currency")
        fun step(index: Int) {
            if (index >= types.size) {
                result.success(
                    mapOf(
                        "skus" to report,
                        "projectId" to XSOLLA_PROJECT_ID.toString(),
                        "sdkBundled" to isSdkBundled(),
                        "connected" to (billingClient != null),
                    ),
                )
                return
            }
            queryByType(client, sku, types[index]) { product, note ->
                report[types[index]] = if (product != null) {
                    val id = runCatching {
                        product.javaClass.getMethod("getProductId").invoke(product) as? String
                    }.getOrNull()
                    val type = runCatching {
                        product.javaClass.getMethod("getProductType").invoke(product) as? String
                    }.getOrNull()
                    "FOUND id=$id type=$type"
                } else {
                    note ?: "empty"
                }
                step(index + 1)
            }
        }
        step(0)
    }

    /// One `queryProductDetailsAsync` call for [sku] as [productType].
    private fun queryByType(
        client: Any,
        sku: String,
        productType: String,
        onResult: (product: Any?, note: String?) -> Unit,
    ) {
        val productClass = sdkClass("QueryProductDetailsParams\$Product")
        val paramsClass = sdkClass("QueryProductDetailsParams")
        val listenerClass = sdkClass("ProductDetailsResponseListener")
        val billingClientClass = sdkClass("BillingClient")

        // Builders are separate classes from the types that create them, so
        // every setter must be looked up on the builder instance's own class.
        // Looking them up on the outer class throws NoSuchMethodException
        // naming the outer type — which the sheet then showed as a payment
        // error.
        val productBuilder = productClass.getMethod("newBuilder").invoke(null)
        productBuilder.javaClass.getMethod("setProductId", String::class.java)
            .invoke(productBuilder, sku)
        productBuilder.javaClass.getMethod("setProductType", String::class.java)
            .invoke(productBuilder, productType)
        val product = productBuilder.javaClass.getMethod("build").invoke(productBuilder)

        val paramsBuilder = paramsClass.getMethod("newBuilder").invoke(null)
        paramsBuilder.javaClass.getMethod("setProductList", List::class.java)
            .invoke(paramsBuilder, listOf(product))
        val params = paramsBuilder.javaClass.getMethod("build").invoke(paramsBuilder)

        val listener = java.lang.reflect.Proxy.newProxyInstance(
            classLoader,
            arrayOf(listenerClass),
        ) { _, method, args ->
            if (method.name == "onProductDetailsResponse" && args != null && args.size == 2) {
                @Suppress("UNCHECKED_CAST")
                val products = args[1] as? List<Any?>
                val product = products?.firstOrNull()
                // An empty list is not the same as "no such item": a type
                // mismatch, an auth failure and an empty catalogue all arrive
                // this way. The response code and debug message are the only
                // place the difference is stated.
                var note: String? = null
                if (product == null) {
                    val result = args[0]
                    val code = try {
                        result?.javaClass?.getMethod("getResponseCode")?.invoke(result) as? Int
                    } catch (_: Throwable) { null }
                    val detail = try {
                        result?.javaClass?.getMethod("getDebugMessage")?.invoke(result) as? String
                    } catch (_: Throwable) { null }
                    note = "code=$code ${detail ?: "(no message)"}"
                    android.util.Log.w("XsollaBridge", "no product for $sku as $productType: $note")
                }
                onResult(product, note)
            }
            null
        }

        billingClientClass
            .getMethod("queryProductDetailsAsync", paramsClass, listenerClass)
            .invoke(client, params, listener)
    }

    /// Pay Station answered with nothing for every catalogue type we tried.
    ///
    /// The note list carries the server's own code and message per type; it is
    /// the difference between "wrong item type", "not signed in" and "empty
    /// catalogue", which all look identical in an empty product list.
    private fun failSkuUnavailable(sku: String, attempts: List<String>) {
        val detail = if (attempts.isEmpty()) "" else " Server said: " + attempts.joinToString("; ")
        failPending(
            "SKU_UNAVAILABLE",
            "Xsolla returned no product for \"$sku\" in project $XSOLLA_PROJECT_ID.$detail",
        )
    }

    private fun launchFlow(productDetails: Any) {
        val client = billingClient ?: run {
            failPending("XSOLLA_INIT", "Billing client is gone")
            return
        }
        try {
            val detailsParamsClass = sdkClass("BillingFlowParams\$ProductDetailsParams")
            val flowParamsClass = sdkClass("BillingFlowParams")
            val billingClientClass = sdkClass("BillingClient")

            val detailsBuilder = detailsParamsClass.getMethod("newBuilder").invoke(null)
            detailsBuilder.javaClass.getMethod(
                "setProductDetails",
                sdkClass("ProductDetails"),
            ).invoke(detailsBuilder, productDetails)
            val detailsParams = detailsBuilder.javaClass.getMethod("build").invoke(detailsBuilder)

            val flowBuilder = flowParamsClass.getMethod("newBuilder").invoke(null)
            flowBuilder.javaClass.getMethod("setProductDetailsParamsList", List::class.java)
                .invoke(flowBuilder, listOf(detailsParams))
            val flowParams = flowBuilder.javaClass.getMethod("build").invoke(flowBuilder)

            // launchBillingFlow returns a BillingResult; a non-OK code means the
            // sheet never opened (the listener will not fire in that case).
            val billingResult = billingClientClass
                .getMethod("launchBillingFlow", Activity::class.java, flowParamsClass)
                .invoke(client, this, flowParams)
            val code = billingResult.javaClass.getMethod("getResponseCode").invoke(billingResult) as Int
            if (code != 0) { // BillingResponseCode.OK
                val message = billingResult.javaClass.getMethod("getDebugMessage")
                    .invoke(billingResult) as? String
                failPending("XSOLLA_FLOW", message ?: "Billing flow refused (code $code)")
            }
        } catch (e: Throwable) {
            failPending("XSOLLA_FLOW", e.message ?: "Could not open the Pay Station sheet")
        }
    }

    /** PurchasesUpdatedListener → Dart. Success is reported per purchase. */
    private fun handlePurchasesUpdated(args: Array<out Any?>?) {
        val billingResult = args?.getOrNull(0) ?: return
        val purchases = args.getOrNull(1) as? List<*>
        val code = billingResult.javaClass.getMethod("getResponseCode").invoke(billingResult) as Int

        if (code != 0 || purchases.isNullOrEmpty()) { // not OK / nothing bought
            val message = billingResult.javaClass.getMethod("getDebugMessage")
                .invoke(billingResult) as? String
            failPending(
                if (code == 1) "XSOLLA_CANCELLED" else "XSOLLA_PURCHASE",
                message ?: "Purchase not completed (code $code)",
            )
            return
        }

        val purchase = purchases.firstOrNull()
        if (purchase == null) {
            failPending("XSOLLA_PURCHASE", "Purchase list was empty")
            return
        }
        val token = purchase.javaClass.getMethod("getPurchaseToken").invoke(purchase) as? String
        failOrSucceed(token)
    }

    /// Coin packs are consumable: without consuming, the store considers the
    /// product owned and the next purchase of the same pack is refused. The
    /// grant itself is idempotent in Firestore on the purchase token, so
    /// consuming cannot double-credit.
    private fun consume(purchaseToken: String, onDone: () -> Unit) {
        val client = billingClient
        if (client == null) {
            onDone()
            return
        }
        try {
            val paramsClass = sdkClass("ConsumeParams")
            val listenerClass = sdkClass("ConsumeResponseListener")
            val builder = paramsClass.getMethod("newBuilder").invoke(null)
            builder.javaClass.getMethod("setPurchaseToken", String::class.java)
                .invoke(builder, purchaseToken)
            val params = builder.javaClass.getMethod("build").invoke(builder)

            val listener = java.lang.reflect.Proxy.newProxyInstance(
                classLoader,
                arrayOf(listenerClass),
            ) { _, method, args ->
                if (method.name == "onConsumeResponse") {
                    val code = args?.getOrNull(0)?.javaClass
                        ?.getMethod("getResponseCode")?.invoke(args[0]) as? Int
                    if (code != 0) {
                        android.util.Log.w("XsollaBridge", "consume returned code $code")
                    }
                    onDone()
                }
                null
            }
            sdkClass("BillingClient")
                .getMethod("consumeAsync", paramsClass, listenerClass)
                .invoke(client, params, listener)
        } catch (e: Throwable) {
            // A failed consume must not fail the purchase: the grant is already
            // earned. It only means the pack may need support to re-buy.
            android.util.Log.w("XsollaBridge", "consume failed", e)
            onDone()
        }
    }

    private fun failOrSucceed(purchaseToken: String?) {
        val result = pendingResult
        val sku = pendingSku
        pendingResult = null
        pendingSku = null
        if (result == null) return
        if (purchaseToken.isNullOrBlank()) {
            result.error("XSOLLA_PURCHASE", "Purchase returned without a token", null)
            return
        }
        // Firestore (lib/services/game_store.dart) records the entitlement; this
        // layer never grants coins itself. Consume first for the coin packs so
        // the same pack can be bought again.
        val consumeFirst = sku == null || !sku.startsWith("multimedia")
        if (consumeFirst) {
            consume(purchaseToken) {
                result.success(
                    mapOf("sku" to sku, "purchaseToken" to purchaseToken),
                )
            }
        } else {
            result.success(
                mapOf("sku" to sku, "purchaseToken" to purchaseToken),
            )
        }
    }

    private fun failPending(code: String, message: String) {
        val result = pendingResult
        pendingResult = null
        pendingSku = null
        result?.error(code, message, null)
    }

}
