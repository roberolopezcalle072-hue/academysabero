# SABERO ACADEMY

Base del campus privado de SABERO Consulting. La landing es pública. Las rutas `/campus` y `/admin` requieren una identidad de Google verificada y una membresía activa. La administración exige además el rol `admin`.

## Arquitectura

```text
Navegador ── HTTPS ── Astro (landing estática + campus SSR)
                          │
                          ├── OAuth con Supabase Auth y Google
                          │
                          └── API REST privada ── NestJS (monolito modular)
                                                     │
                                                     ├── Supabase Auth (verificación)
                                                     └── PostgreSQL de Supabase (RLS)
```

| Carpeta | Responsabilidad |
| --- | --- |
| `frontend/src/pages` y `middleware.ts` | Rutas Astro y control de acceso previo al renderizado SSR. |
| `frontend/src/features/access` | Modelo de membresía, decisión de sesión y adaptadores SSR para Supabase y la API. |
| `frontend/src/shared` | Layout, estilos globales y configuración del servidor. |
| `backend/src/modules/access` | Caso de uso de acceso, puerto de identidad, adaptador Supabase y controlador REST. |
| `backend/src/modules/health` | Comprobación de disponibilidad del proceso. |
| `supabase/migrations` | Cambios versionados de PostgreSQL y políticas RLS. |

La capa de aplicación de NestJS depende de un contrato de identidad. El módulo enlaza el contrato con Supabase en el arranque. En Astro, el caso de uso recibe operaciones de lectura de sesión y consulta de membresía como dependencias. Astro se comunica con NestJS por HTTP y cada aplicación tiene su propio manifiesto de dependencias.

El inicio de sesión usa PKCE y cookies HttpOnly, SameSite=Lax y Secure bajo HTTPS. Astro envía el token de acceso a NestJS desde el servidor. NestJS valida el token con Supabase Auth y consulta la membresía con el token del usuario. Las políticas RLS comprueban el rol y una sesión de Google vigente. Para alumnos exigen además un correo autorizado y una matrícula activa. Las cuentas autenticadas no pueden modificar sus roles.

### Límites de módulos

| Módulo | Responsabilidad | Estado |
| --- | --- | --- |
| Acceso | Identidad, membresía y rol del campus. | Implementado |
| Salud | `GET /api/v1/health`, disponibilidad del proceso. | Implementado |
| Alumnos | Perfil académico y gestión de alumnos. | Definido |
| Cursos | Catálogo privado, estructura y publicación de cursos. | Definido |
| Matrículas | Relación alumno–curso y vigencia del acceso. | Definido |
| Progreso | Avance y finalización por alumno y actividad. | Definido |
| Sesiones | Agenda y enlaces de Google Meet. | Definido |
| Recursos | Metadatos y referencias de Google Drive para documentos, prompts y grabaciones. | Definido |
| Consultas | Conversaciones entre alumnos y administración. | Definido |

Cada módulo nuevo debe poseer sus reglas y acceder a otros módulos mediante sus contratos de aplicación. Matrículas decidirá el acceso a contenidos por curso. Para Google Drive, el acceso al archivo dependerá también de los permisos configurados en Google. Las imágenes de marca se servirán como archivos locales cuando se incorporen.

## Ejecutar en desarrollo

Requisitos: Node.js 24 recomendado y un proyecto Supabase con Google OAuth configurado.

1. Copia `backend/.env.example` a `backend/.env` y `frontend/.env.example` a `frontend/.env`. En ambos, configura la URL y clave **publicable** del mismo proyecto Supabase.
2. Aplica las migraciones de `supabase/migrations/` en orden ascendente en el SQL Editor del proyecto. Consulta el [modelo de datos y su verificación](supabase/MODELO.md).
3. Activa Google en Supabase Auth y configura las credenciales OAuth de Google allí. En Google Cloud, registra la URI de callback de Supabase que muestra el proveedor. En Supabase, permite `http://localhost:4321/auth/callback` para desarrollo y `https://academy.saberoconsulting.com/auth/callback` para producción. Usa como Site URL el origen correspondiente al entorno. [Google OAuth en Supabase](https://supabase.com/docs/guides/auth/social-sign-in/auth-google) · [URLs de redirección](https://supabase.com/docs/guides/auth/redirect-urls)
4. Inicia los dos procesos en terminales separadas.

```sh
cd backend
npm ci
npm run dev
```

```sh
cd frontend
npm ci
npm run dev
```

Abre http://localhost:4321. Antes del primer acceso, habilita el hook de Supabase y vincula la primera cuenta administrativa siguiendo la [guía de acceso privado](supabase/ACCESO.md).

La API de NestJS escucha en `127.0.0.1:3000`. `GET /api/v1/access/me` requiere un token bearer de Supabase y devuelve el identificador y rol de una membresía activa. Devuelve 401 para sesiones inválidas, 403 para cuentas sin acceso y 503 si falla la consulta al proveedor. Para verificación local, ejecuta `npm run check` y `npm run build` en cada carpeta.

## Variables de entorno

| Variable | Aplicación | Uso |
| --- | --- | --- |
| `SUPABASE_URL` | Ambas | URL del proyecto. |
| `SUPABASE_PUBLISHABLE_KEY` | Ambas | Clave publicable. RLS determina el acceso a datos. |
| `SITE_URL` | Frontend | Origen público. Define el callback, la validación de origen y el atributo Secure de las cookies. |
| `API_BASE_URL` | Frontend | URL interna de NestJS incluida la ruta `/api/v1`. |
| `HOST`, `PORT` | Ambas | Dirección y puerto del servidor. En desarrollo, Astro usa los valores predeterminados de su CLI. |

## VPS Linux

En el VPS, configura `SITE_URL=https://academy.saberoconsulting.com` en el frontend. Ejecuta `docker compose up -d --build` si hay recursos suficientes para construir las imágenes. El backend queda en la red interna de Compose y Astro se publica en loopback. Para una instalación sin contenedores, usa `npm ci && npm run build` y supervisa `npm start` para cada aplicación con el gestor de procesos del VPS.

En Namecheap, apunta el subdominio `academy` a la IP del VPS. Configura el proxy HTTPS existente para enviar el tráfico del dominio a `127.0.0.1:4321` y preservar el host público y el protocolo HTTPS mediante `Host`, `X-Forwarded-Host` y `X-Forwarded-Proto`. Excluye las rutas dinámicas de autenticación y del campus de la caché del proxy. PostgreSQL permanece en Supabase. El despliegue utiliza únicamente los procesos de Astro y NestJS.

## Publicación y campus

El panel /admin/cursos permite editar el programa público, cursos, módulos, lecciones y materiales. Consulta la [guía de publicación, campus y Google Drive](supabase/CAMPUS.md).

## Sistema visual

Los tokens y componentes básicos están en `frontend/src/shared/styles/global.css`. La landing, el inicio de sesión y los paneles comparten tipografía, navegación, espaciados, estados de foco, separadores y botones rectangulares. La paleta base respeta los seis colores corporativos e incorpora un azul más oscuro para texto y botones sobre fondos claros. La implementación se basó en la descripción visual porque la captura de referencia no estaba disponible en el espacio de trabajo.

## Pagos con pasarela

El cobro es independiente del proveedor. El backend define el contrato `PaymentProvider` (`backend/src/modules/payments/application/payment-provider.ts`) y cada pasarela es un adaptador (`culqi-provider.ts`). Flujo: el alumno completa sus datos y acepta los términos → el backend crea el pago (`academy_start_payment`) → el navegador abre el formulario de la pasarela y obtiene un token → el backend cobra con la llave secreta y confirma el pago en la base con un secreto interno (`academy_confirm_payment`), que activa la matrícula. Un cobro simultáneo se bloquea con el estado `processing`.

| Variable (backend) | Uso |
| --- | --- |
| `PAYMENT_PROVIDER` | `culqi`, o vacío para desactivar el pago en línea (queda la solicitud manual). `mock` solo en desarrollo. |
| `CULQI_PUBLIC_KEY`, `CULQI_SECRET_KEY` | Llaves de Culqi. Ambas de prueba (`pk_test_`/`sk_test_`) o ambas de producción. |
| `PAYMENT_INTERNAL_SECRET` | Secreto que autoriza al backend a confirmar pagos. Su SHA-256 está en `academy_internal_secrets`. |

Para cambiar de pasarela: escribir un adaptador que implemente `PaymentProvider`, registrarlo en `provider-factory.ts` y añadir su apertura de formulario en `frontend/src/features/payments/checkout.ts`. La base de datos y las pantallas no cambian.

## Correo (Resend)

El backend envía correos con un adaptador intercambiable (`backend/src/modules/mail`): `EmailProvider` + `ResendProvider`. Si no hay `EMAIL_PROVIDER`, el sistema funciona igual y solo registra en el log "Correo no enviado". Un correo caído nunca bloquea un pago ni un reclamo.

Correos que envía: pago confirmado (al alumno, con enlace a su constancia) y aviso de pago (a `EMAIL_ADMIN_TO`); copia de la hoja de reclamación al consumidor y aviso al administrador; respuesta al consumidor cuando el administrador responde un reclamo; aviso de solicitudes de inscripción manuales.

| Variable (backend) | Uso |
| --- | --- |
| `EMAIL_PROVIDER` | `resend`, o vacío para no enviar correos. |
| `RESEND_API_KEY` | Llave de Resend (`re_…`). |
| `EMAIL_FROM` | Remitente, por ejemplo `"SABERO Academy <no-reply@saberoconsulting.com>"`. El dominio debe estar verificado en Resend. |
| `EMAIL_ADMIN_TO` | Correo que recibe los avisos y al que responden los alumnos. |
| `SITE_URL` | Origen público, para los enlaces y el logo de los correos. |

Probar sin tocar el servidor: `node deploy/test-email.mjs tucorreo@gmail.com`. Subir la configuración: `bash deploy/push-backend-env.sh`.

## Constancia de pago

Cada pago confirmado recibe un número correlativo (`academy_payments.receipt_number`) y el alumno puede ver e imprimir su constancia en `/cuenta/comprobante/<id>` (diseño de comprobante, con los datos de `COMPANY` en `frontend/src/features/landing/content.ts`). **No es una boleta ni una factura electrónica de SUNAT**: esas se emiten por separado. Antes del lanzamiento, reinicia la numeración con `alter sequence public.academy_receipt_seq restart with 1;`.
