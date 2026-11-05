package com.cauce.cauce_stream

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import java.net.NetworkInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channelName = "cauce_stream/device"
    private val powerChannelName = "cauce.power/power"

    private val adminComponent: ComponentName
        get() = ComponentName(this, CauceDeviceAdminReceiver::class.java)

    private fun devicePolicyManager(): DevicePolicyManager =
        getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceName" -> {
                        // Nombre configurado del dispositivo, tal cual lo
                        // expone el SO; en TV boxes suele venir vacío y se
                        // usa el modelo como fallback.
                        val name = Settings.Global.getString(
                            contentResolver,
                            "device_name"
                        ) ?: Build.MODEL
                        result.success(name)
                    }
                    "getMacAddress" -> {
                        // MAC real de la interfaz activa para Wake-on-LAN
                        // del lado del servidor. WifiManager devuelve
                        // 02:00:00:00:00:00 desde Android 6 (privacidad),
                        // así que no se usa; se lee de NetworkInterface.
                        result.success(activeMacAddress())
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, powerChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "wakeScreen" -> {
                        // Encender la pantalla (action "on"). La app sigue
                        // ejecutándose con la pantalla en espera (los
                        // heartbeats siguen llegando), así que el canal
                        // atiende el comando aunque la activity esté
                        // pausada. Idempotente: pantalla ya encendida es
                        // éxito.
                        wakeScreen()
                        result.success(true)
                    }
                    "enterStandby" -> {
                        // Apagar la pantalla (action "off") vía el
                        // DevicePolicyManager.goToSleep() oculto del
                        // framework (por reflexión) cuando la app está
                        // aprovisionada como Device Owner / Device Admin;
                        // si no, false y el cliente responde
                        // power.error/standby_denied.
                        result.success(enterStandby())
                    }
                    "getPowerCapabilities" -> {
                        result.success(powerCapabilities())
                    }
                    "requestDeviceAdmin" -> {
                        result.success(requestDeviceAdmin())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Apagar la pantalla (action "off").
    ///
    /// Android NO ofrece API pública compilable para que una app ponga la
    /// pantalla en espera: DevicePolicyManager.goToSleep(long) es @hide en
    /// el SDK público (no resuelve contra android.jar), pero existe en el
    /// framework y se invoca por reflexión. El chequeo de permisos del
    /// servicio pasa solo cuando la app es Device Owner (aprovisionamiento
    /// por ADB/QR; ver client/docs/device_owner_setup.md) o, en la mayoría
    /// de los OEM, con Device Admin activo. Sin aprovisionamiento (o si el
    /// OEM retiró el método oculto) devuelve false: el cliente responde
    /// power.error/standby_denied. Sin workarounds (overlay negro).
    private fun enterStandby(): Boolean {
        val dpm = devicePolicyManager()
        val aprovisionado =
            dpm.isDeviceOwnerApp(packageName) || dpm.isAdminActive(adminComponent)
        if (!aprovisionado) return false
        return try {
            // time = 0: duerme hasta el próximo evento de wake (power.command
            // "on" con wake lock ACQUIRE_CAUSES_WAKEUP, IR del control, toque).
            val goToSleep = DevicePolicyManager::class.java
                .getMethod("goToSleep", Long::class.javaPrimitiveType)
            goToSleep.invoke(dpm, 0L)
            true
        } catch (e: Exception) {
            // NoSuchMethodException (OEM sin el método oculto), SecurityException
            // (sin privilegios de administración), InvocationTargetException
            // (el servicio lo rechazó): no permitido, jamás éxito falso.
            false
        }
    }

    /// Capacidades reales de energía, para diagnóstico y para que la app
    /// sepa qué le falta aprovisionar antes de poder apagar la pantalla.
    private fun powerCapabilities(): Map<String, Any> {
        val dpm = devicePolicyManager()
        val owner = dpm.isDeviceOwnerApp(packageName)
        val adminActive = dpm.isAdminActive(adminComponent)
        return mapOf(
            // Wake lock con ACQUIRE_CAUSES_WAKEUP es API pública: encender
            // la pantalla siempre está soportado.
            "can_wake" to true,
            "can_standby" to (owner || adminActive),
            "device_owner" to owner,
            "admin_active" to adminActive,
        )
    }

    /// Lanza el diálogo del sistema para activar la app como Device Admin
    /// clásico (ACTION_ADD_DEVICE_ADMIN). Devuelve true si ya estaba activo
    /// o si el flujo se lanzó. Ojo: esto da Device Admin, no Device Owner;
    /// para Owner hace falta aprovisionamiento por ADB/QR (ver doc).
    private fun requestDeviceAdmin(): Boolean {
        val dpm = devicePolicyManager()
        if (dpm.isDeviceOwnerApp(packageName) || dpm.isAdminActive(adminComponent)) {
            return true
        }
        return try {
            startActivity(
                Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                    putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, adminComponent)
                    putExtra(
                        DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                        "Cauce Stream necesita administración del dispositivo para " +
                            "poder apagar la pantalla de forma remota."
                    )
                }
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    /// MAC (upper-case, con ':') de la primera interfaz activa no
    /// loopback; null si ninguna tiene hardware address.
    private fun activeMacAddress(): String? {
        return try {
            val interfaces = NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
            for (iface in interfaces) {
                if (!iface.isUp || iface.isLoopback) continue
                val hw = iface.hardwareAddress
                if (hw != null && hw.isNotEmpty()) {
                    return hw.joinToString(":") { "%02X".format(it) }
                }
            }
            null
        } catch (e: Exception) {
            null
        }
    }

    /// Enciende la pantalla desde código. Con la activity pausada la
    /// ruta fiable es un wake lock con ACQUIRE_CAUSES_WAKEUP (API
    /// pública, permiso normal WAKE_LOCK); los flags de activity
    /// aseguran que la app sea lo que se muestre al volver la pantalla.
    /// El wake lock se libera solo por timeout: solo enciende, no se
    /// retiene.
    private fun wakeScreen() {
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        if (powerManager.isInteractive) return

        @Suppress("DEPRECATION")
        val wakeLock = powerManager.newWakeLock(
            PowerManager.FULL_WAKE_LOCK
                or PowerManager.ACQUIRE_CAUSES_WAKEUP
                or PowerManager.ON_AFTER_RELEASE,
            "cauce:power:wake"
        )
        wakeLock.acquire(3_000L)

        runOnUiThread {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setTurnScreenOn(true)
                setShowWhenLocked(true)
            } else {
                @Suppress("DEPRECATION")
                window.addFlags(
                    WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED
                        or WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
                )
            }
        }
    }
}
