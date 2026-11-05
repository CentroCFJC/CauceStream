# Aprovisionar el cliente como Device Owner (apagado real de pantalla)

Android no permite que una app arbitraria apague la pantalla. La única ruta
es `DevicePolicyManager.goToSleep()`, que es un método **oculto (@hide)** en
el SDK público: no compila contra `android.jar`, pero existe en el framework
y el cliente lo invoca por reflexión; la llamada solo prospera cuando la app
está aprovisionada como **Device Owner** (garantizado) o **Device Admin**
activo (funciona en la mayoría de los OEM). El cliente ya declara el
`CauceDeviceAdminReceiver` en el manifest; falta el aprovisionamiento, que
se hace una sola vez por dispositivo.

Con Device Owner, `power.command` "off" apaga la pantalla de verdad y
"on" la enciende (wake lock, ya soportado sin aprovisionamiento). La app
sigue corriendo con la pantalla apagada: heartbeats y WebSocket siguen
activos, así que el servidor puede volver a encenderla.

## Requisitos previos del box (antes de aprovisionar)

1. **APK actualizado instalado.** Si `set-device-owner` responde
   `Unknown admin: ComponentInfo{com.cauce.cauce_stream/...CauceDeviceAdminReceiver}`,
   el box tiene instalada una versión vieja de la app, sin el receiver.
   Instalar primero el APK nuevo y verificar que el sistema ya conoce el
   receiver:

   ```powershell
   adb -s <ip-del-box>:5555 install -r "D:\CauceStream\client\build\app\outputs\flutter-apk\app-debug.apk"
   # (-r reinstala conservando datos; si falla por downgrade, agregar -d)
   adb -s <ip-del-box>:5555 shell "dumpsys package com.cauce.cauce_stream | grep -i CauceDeviceAdminReceiver"
   ```

2. **Un solo usuario en el dispositivo.** Si responde
   `Not allowed to set the device owner because there are already several
   users on the device`, hay usuarios secundarios: listarlos y eliminar
   todos los que no sean el user 0:

   ```powershell
   adb -s <ip-del-box>:5555 shell pm list users
   adb -s <ip-del-box>:5555 shell pm remove-user <id>   # repetir para cada id != 0
   ```

   Si un usuario no se puede eliminar (p. ej. perfil de trabajo de otro
   administrador), el box ya está administrado por otro Device Owner y no
   se puede tener dos.

3. **Ninguna cuenta registrada en el user 0.** Si responde
   `Not allowed to set the device owner because there are already some
   accounts on the device`, hay cuentas (Google, TCL, etc.) en el perfil
   principal. Android bloquea el aprovisionamiento en ese caso y **no hay
   comando ADB público para borrar cuentas**. Ver las cuentas:

   ```powershell
   adb -s <ip-del-box>:5555 shell dumpsys account | Select-String "Account {"
   ```

   Hay tres salidas posibles:

   - **Opción A (sin reset, recomendada si el box ya está configurado):**
     quitar todas las cuentas desde la UI del TV (Ajustes > Cuentas y
     perfiles > cada cuenta > Quitar; elegir "quitar y quedar sin conexión",
     NUNCA "quitar y restablecer el dispositivo"), luego repetir
     `set-device-owner`. Algunas cuentas de sistema de OEM no se pueden
     quitar; si tras quitarlas todas sigue el error, pasar a la opción B.
   - **Opción B (flujo garantizado para flotas):** factory reset por ADB y
     aprovisionar ANTES de añadir ninguna cuenta:

     ```powershell
     adb -s <ip-del-box>:5555 shell "am broadcast -a android.intent.action.MASTER_CLEAR -n android/com.android.server.MasterClearReceiver"
     # (si no funciona, agregar -p android antes de -a; en algunos modelos
     #  hace falta root o entrar al recovery con: adb reboot recovery)
     # Tras el reset: configurar lo mínimo SIN iniciar sesión en ninguna
     # cuenta, habilitar ADB por red (adb tcpip 5555), instalar el APK y
     # enseguida: dpm set-device-owner ...
     ```
   - **Opción C (sin Device Owner):** activar la app como **Device Admin
     clásico** (no owner): desde la app, método `requestDeviceAdmin` del
     canal `cauce.power/power` (lanza el diálogo del sistema), o a mano en
     Ajustes > Seguridad > Administradores del dispositivo. No tiene la
     restricción de cuentas y en la mayoría de los OEM (TCL incluido)
     `goToSleep()` por reflexión funciona con admin activo. Verificar con
     `dumpsys device_policy` (sección "Enabled Device Admins") y probando
     un `power.command` "off".

## Método recomendado: ADB (despliegue masivo)

En cada TV box, una vez (por USB o con ADB por red habilitado):

```powershell
# Habilitar ADB por TCP (una vez por box; en muchos boxes basta con USB)
adb tcpip 5555
adb connect <ip-del-box>:5555

# Aprovisionar la app como Device Owner.
# OJO con las comillas: `adb shell` concatena sus argumentos y las
# comillas de --name "Cauce Stream" se pierden (el comando llega como
# ... --name Cauce Stream com... y falla con "Invalid component Stream").
# Pasar TODO el comando como un único argumento con comillas simples
# internas, o simplemente omitir --name (es cosmético):
adb -s <ip-del-box>:5555 shell "dpm set-device-owner --user current --name 'Cauce Stream' com.cauce.cauce_stream/.CauceDeviceAdminReceiver"
# equivalente sin nombre:
adb -s <ip-del-box>:5555 shell dpm set-device-owner --user current com.cauce.cauce_stream/.CauceDeviceAdminReceiver

# Verificar
adb -s <ip-del-box>:5555 shell dumpsys device_policy
# Debe aparecer com.cauce.cauce_stream/.CauceDeviceAdminReceiver como Device Owner
```

Comprobación equivalente desde la app: al arrancar, el log imprime
`[CAUCE] Capacidades de energía: ... device_owner=true can_standby=true`.

También se puede verificar desde la app: al arrancar, el log imprime
`[CAUCE] Capacidades de energía: ... device_owner=true can_standby=true`.

Si el box ya tiene otro Device Owner (p. ej. un MDM de fábrica), no se
puede tener dos; hay que desvincularlo primero (solo si el equipo es de
la institución):

```powershell
adb shell dpm remove-active-admin <paquete-del-owner-actual>/.<receiver-actual>
```

Si el box ya reporta `Device owner has already been set` / `already
provisioned`, hay otro owner activo: no se pueden tener dos.

## Método alternativo: Device Admin clásico (manual, por app)

Desde la app se puede llamar al canal `cauce.power/power` con el método
`requestDeviceAdmin`: lanza el diálogo del sistema
(`ACTION_ADD_DEVICE_ADMIN`) para activar la app como administradora.
Con admin activo, `goToSleep()` funciona en la mayoría de los equipos,
pero no está garantizado por la plataforma: **Device Owner es el caso
seguro**. También se puede activar a mano en
Ajustes > Seguridad > Administradores del dispositivo.

## Qué NO hace Device Owner

- No apaga el equipo, solo la pantalla (`goToSleep(0)` duerme la pantalla
  hasta el siguiente evento de wake: `power.command` "on", IR del control,
  toque).
- No despierta un SoC en suspensión profunda; para eso hace falta un
  evento de hardware (WoWLAN, RTC, IR).
