package com.cauce.cauce_stream

import android.app.admin.DeviceAdminReceiver

/// Receiver de administración de dispositivo. Estar declarado en el
/// manifest (con res/xml/device_admin.xml) es lo que permite aprovisionar
/// la app como Device Owner (ADB/QR) o activarla como Device Admin desde
/// el diálogo del sistema; sin él, ninguna app puede llamar
/// DevicePolicyManager.goToSleep() para apagar la pantalla.
///
/// Ver client/docs/device_owner_setup.md para el aprovisionamiento.
class CauceDeviceAdminReceiver : DeviceAdminReceiver()
