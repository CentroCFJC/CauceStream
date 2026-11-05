# Cauce — Contexto del sistema

## 1. Propósito

**Cauce** es un sistema de administración y operación para una sala de experiencias interactivas y audiovisuales del **Centro de Ciencias Francisco José de Caldas (CCFJC)**, ubicada en el Centro Cultural Rogelio Salmona.

El sistema busca centralizar la supervisión, configuración y operación de los diferentes dispositivos y experiencias que conforman la sala.

Cauce debe funcionar principalmente dentro de la red local de la sala y debe mantener sus funciones esenciales incluso cuando no exista conexión a Internet.

El backend se ejecuta en un PC servidor local de la infraestructura de la sala.

## 2. Contexto físico

La Sala Cauce puede contener diferentes tipos de dispositivos y experiencias, entre ellos:

- Pantallas y televisores.
- Equipos Windows.
- Dispositivos Android.
- Equipos táctiles.
- Raspberry Pi.
- Dispositivos de realidad virtual.
- Otros dispositivos conectados a la red local.
- Dispositivos IoT o microcontroladores que puedan incorporarse posteriormente.

Los dispositivos ejecutan aplicaciones cliente desarrolladas específicamente para Cauce o integradas con el ecosistema de la sala.

El sistema no debe asumir que todos los dispositivos utilizan el mismo sistema operativo o protocolo de comunicación.

## 3. Arquitectura general

La arquitectura conceptual está compuesta por:

    Servidor Cauce
    FastAPI
    PostgreSQL
          |
          | Red local
          |
    +-----+-----+-----+
    |           |     |
    v           v     v
 Dispositivo  Dispositivo  Dispositivo
   cliente      cliente      cliente

Además, existen aplicaciones móviles que funcionan como clientes de administración y operación del sistema.

El servidor centraliza la información y coordinación del sistema.

## 4. Funcionamiento dentro de la red local

La red local es un componente fundamental del sistema.

Cauce debe poder operar sin depender permanentemente de servicios externos.

La pérdida de acceso a Internet no debe impedir:

- Consultar el estado de los dispositivos.
- Comunicarse con dispositivos dentro de la LAN.
- Ejecutar las funciones principales del sistema.
- Mantener la configuración almacenada localmente.
- Operar las experiencias que no dependan explícitamente de un servicio externo.

Internet puede utilizarse para funciones complementarias cuando esté disponible, pero no debe considerarse un requisito permanente para la operación local.

## 5. Servidor

El backend de Cauce se desarrolla con:

- Python.
- FastAPI.
- SQLAlchemy 2.x asíncrono.
- asyncpg.
- PostgreSQL.
- Alembic.

El servidor es la fuente central de información persistente del sistema.

La aplicación backend seguirá una arquitectura modular:

    API
     ↓
    Services
     ↓
    Repositories
     ↓
    SQLAlchemy Async
     ↓
    PostgreSQL

Las sesiones de base de datos se gestionan mediante inyección de dependencias de FastAPI.

La lógica de negocio no debe quedar directamente dentro de los endpoints.

## 6. Dispositivos

Un **dispositivo** representa un equipo físico que participa en una experiencia de Cauce.

Cada dispositivo puede tener información como:

- Identificador.
- Nombre.
- Tipo.
- Dirección IP actual.
- Puerto o puertos utilizados.
- Sistema operativo o plataforma.
- Aplicación cliente instalada.
- Versión de la aplicación.
- Estado operativo.
- Última comunicación con el servidor.
- Configuración específica.

La dirección IP de un dispositivo puede cambiar.

Por esta razón, la IP no debe utilizarse como identificador permanente del dispositivo.

El sistema debe identificar los dispositivos mediante un identificador propio y permitir actualizar su información de conexión.

## 7. Autoconfiguración de dispositivos

Los dispositivos cliente conocen la dirección del servidor Cauce y pueden comunicarse con él.

Durante el registro o funcionamiento normal, un dispositivo puede enviar información que permita al servidor conocer o actualizar datos como:

- Identidad del dispositivo.
- Dirección IP.
- Puerto.
- Información de la aplicación cliente.
- Estado.
- Capacidades.

El sistema debe estar preparado para que un dispositivo pueda actualizar automáticamente su información de conexión cuando esta cambie.

También debe existir una alternativa de configuración manual para situaciones en las que la autoconfiguración falle.

No se debe asumir que existe descubrimiento automático de dispositivos en la red.

## 8. Heartbeat

Los dispositivos cliente enviarán periódicamente información al servidor para indicar que continúan disponibles.

El heartbeat permitirá posteriormente determinar:

- Si un dispositivo está activo.
- Cuándo fue su última comunicación.
- Información básica del dispositivo.
- Cambios en su configuración de red.
- Estado de la aplicación cliente.

El backend debe considerar que los heartbeats son operaciones frecuentes y concurrentes.

Por esta razón, el acceso a PostgreSQL utiliza SQLAlchemy asíncrono con asyncpg.

La información histórica de heartbeats puede crecer rápidamente, por lo que su diseño debe considerar volumen y retención cuando se implemente.

## 9. Usuarios

El sistema tendrá dos roles principales:

### Administrador

Usuario responsable de la administración del sistema.

Entre sus responsabilidades estarán:

- Gestionar mediadores.
- Activar o desactivar mediadores.
- Configurar permisos.
- Administrar dispositivos.
- Administrar experiencias.
- Configurar y supervisar la operación de la sala.

### Mediador

Usuario encargado de la operación cotidiana de las experiencias.

Sus capacidades estarán determinadas por los permisos asignados a su rol.

Los roles son parte estable del dominio:

- ADMINISTRADOR
- MEDIADOR

No se espera que los usuarios creen nuevos tipos de roles.

Los permisos, en cambio, sí pueden cambiar con el tiempo.

La autorización debe basarse en permisos y no en comprobaciones dispersas del nombre del rol.

## 10. Experiencias

Una experiencia representa una actividad, instalación o contenido interactivo disponible en la Sala Cauce.

Una experiencia puede involucrar uno o varios dispositivos.

Ejemplos de tipos de experiencia:

- Analógica.
- Audiovisual.
- Realidad aumentada (AR).
- Realidad virtual (VR).
- Interactiva.
- Otras categorías que puedan incorporarse posteriormente.

Una experiencia puede tener información como:

- Nombre.
- Descripción.
- Tipo.
- Estado.
- Dispositivos asociados.
- Configuración específica.
- Contenido asociado.

La definición exacta del modelo de experiencia se realizará posteriormente.

## 11. Operación de dispositivos

El sistema deberá permitir supervisar el estado de los dispositivos y, cuando el dispositivo lo soporte, ejecutar acciones remotas.

Entre las operaciones previstas están:

- Consultar estado.
- Encender o activar.
- Apagar o desactivar.
- Reiniciar.
- Enviar configuración.
- Controlar reproducción.
- Cambiar contenido.
- Ejecutar acciones específicas de una experiencia.

Las capacidades reales dependerán del tipo de dispositivo y de la aplicación cliente.

El backend no debe asumir que todos los dispositivos soportan las mismas operaciones.

## 12. Distribución de contenido

Una funcionalidad futura importante es permitir distribuir contenido hacia uno o varios dispositivos.

El sistema podrá trabajar con:

- Imágenes.
- Videos.
- GIF u otros formatos apropiados.
- Contenido reproducido en bucle.
- Contenido programado.
- Contenido sincronizado entre múltiples pantallas.

Un administrador o mediador autorizado podrá seleccionar el contenido y los dispositivos o experiencias destinatarias.

Esta funcionalidad todavía no forma parte del núcleo inicial del backend.

## 13. Programación

El sistema podrá permitir programar acciones para determinadas fechas y horarios.

Ejemplos:

- Encendido de dispositivos.
- Apagado de dispositivos.
- Inicio de una experiencia.
- Cambio de contenido.
- Reproducción de contenido.
- Acciones recurrentes.

Las tareas programadas deben ejecutarse desde el servidor local y no depender obligatoriamente de Internet.

## 14. Estado en tiempo real

Uno de los objetivos principales de Cauce es proporcionar una visión centralizada del estado de la sala.

El sistema debe poder determinar, entre otros aspectos:

- Qué dispositivos están disponibles.
- Qué dispositivos están desconectados.
- Qué experiencia está asociada a cada dispositivo.
- Cuándo fue la última comunicación.
- Qué contenido se está reproduciendo, cuando el dispositivo pueda reportarlo.
- Qué acciones están pendientes o en ejecución.

Inicialmente puede utilizarse REST y heartbeat.

La utilización de WebSockets u otros mecanismos de comunicación en tiempo real se evaluará cuando exista una necesidad concreta.

## 15. Red e infraestructura

La infraestructura de Cauce se encuentra dentro de una red local administrada por la institución.

Los dispositivos utilizan direcciones IP que pueden ser reservadas o configuradas según la infraestructura de red.

El sistema no debe depender de autodiscovery de red.

El backend debe estar preparado para trabajar con dispositivos cuya IP pueda cambiar.

El servidor debe permanecer accesible dentro de la LAN aunque exista una interrupción del acceso a Internet.

Cuando sea necesario acceder al sistema desde fuera de la red local, podrá utilizarse un mecanismo externo de acceso o túnel, pero este acceso externo no constituye el mecanismo principal de operación de Cauce.

## 16. Principios de diseño

El desarrollo del sistema debe seguir estos principios:

### Separación de responsabilidades

Los endpoints deben encargarse de HTTP.

Los services deben contener la lógica de negocio.

Los repositories deben encargarse del acceso a datos.

### Asincronía

Las operaciones de I/O del backend deben utilizar el enfoque asíncrono establecido.

### Persistencia local

La información fundamental para operar la sala debe almacenarse localmente.

### Tolerancia a cambios de red

La identidad de un dispositivo no debe depender de su IP.

### Evolución incremental

No implementar infraestructura compleja antes de que exista una necesidad real.

### Seguridad

La autenticación, autorización y gestión de credenciales deben tratarse como componentes independientes.

### Configuración

Los parámetros de infraestructura y conexión deben utilizar configuración externa y variables de entorno cuando corresponda.

## 17. Estado actual del proyecto

Actualmente el backend se encuentra en una etapa inicial.

El esqueleto de FastAPI ya está funcionando y la API está disponible mediante `/docs`.

Las decisiones arquitectónicas iniciales incluyen:

- FastAPI.
- SQLAlchemy 2.x asíncrono.
- asyncpg.
- PostgreSQL.
- Alembic.
- Inyección de dependencias mediante `Depends`.
- `AsyncSession` por operación/request.
- Configuración centralizada.
- API bajo `/api`.
- Dependencias de desarrollo separadas del runtime.

El primer módulo funcional del sistema es la gestión de:

- Usuarios.
- Roles.
- Permisos.
- Autenticación.
- Autorización.

Después se desarrollarán progresivamente los módulos de dispositivos, heartbeat, experiencias, contenido y programación.

## 18. Fuera de alcance del backend inicial

No asumir que el backend debe resolver directamente:

- La reproducción audiovisual.
- El renderizado de interfaces.
- El funcionamiento interno de cada dispositivo.
- El control específico de cada fabricante.
- El descubrimiento automático de la red.
- La conexión permanente a Internet.
- La implementación de todas las aplicaciones cliente.

El backend coordina y administra el ecosistema; las aplicaciones cliente ejecutan las capacidades específicas de cada dispositivo.

## 19. Regla para futuras decisiones

Cuando se agregue una nueva funcionalidad al backend, evaluar primero:

1. ¿Es una responsabilidad del servidor o del dispositivo cliente?
2. ¿Debe funcionar sin Internet?
3. ¿Qué información necesita persistirse?
4. ¿Qué permisos requiere?
5. ¿Es específica de un tipo de dispositivo?
6. ¿Debe ejecutarse de forma síncrona o asíncrona?
7. ¿Necesita comunicación en tiempo real?
8. ¿Cómo se comporta ante pérdida de conexión?
9. ¿Puede cambiar la IP o configuración del dispositivo?
10. ¿Puede implementarse sin introducir infraestructura innecesaria?

El objetivo es mantener un backend local, modular, mantenible y orientado a la operación real de la Sala Cauce.