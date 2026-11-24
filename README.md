# Secret Satan — Backend

Backend (Swift + Vapor + SQLite) de la app de amigo secreto.

## Flujo
1. El organizador crea un evento y da de alta a los participantes desde la app iOS
   (nombre, teléfono y, para los niños, el tutor que recibe su enlace).
2. `POST /events/:id/draw` hace el sorteo en el servidor (sin autoasignación,
   respetando exclusiones y sin que un niño regale a su tutor, que es quien recibe su enlace;
   el tutor sí puede regalar al niño).
3. `POST /events/:id/links` genera un enlace de un solo uso por participante; la app los
   comparte con la hoja "Compartir" de iOS (a todos o a uno).
4. Cada persona abre su enlace `https://secretsanta.hdvillamil.dev/r/<token>`, pulsa
   "Mostrar" y ve su amigo secreto. El enlace se consume. Si se pierde, el organizador
   genera uno nuevo (`POST /events/:id/participants/:pid/link`).

## Login (Sign in with Apple / Google)
El organizador entra en la app con Apple o Google. La app envía el **ID token** (JWT) del
proveedor al servidor, que verifica la firma (claves públicas de Apple/Google), el emisor,
la caducidad y la audiencia (`APPLE_BUNDLE_ID` / `GOOGLE_CLIENT_ID`). Si es válido,
devuelve un **token de sesión** propio (30 días, se renueva al usarlo) que la app envía
como `Authorization: Bearer <token>` en el resto de la API.

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/auth/apple` | `{ "idToken": "<identityToken>", "nonce": "<nonce en claro>", "name": "Ana" }` → `{ token, expiresAt, user }` |
| POST | `/auth/google` | `{ "idToken": "<idToken>", "nonce": "<nonce en claro>" }` → `{ token, expiresAt, user }` |
| GET | `/auth/me` | Usuario actual |
| POST | `/auth/logout` | Invalida la sesión actual |
| DELETE | `/auth/me` | Borra la cuenta y todos sus eventos (requisito de App Store) |

- **Nonce** (opcional, recomendado): la app genera un nonce aleatorio, pasa su SHA-256 en hex al
  proveedor (`ASAuthorizationAppleIDRequest.nonce` / `GIDSignIn ... nonce:`) y envía el nonce en
  claro en `nonce`. Si el token lleva nonce, debe coincidir.
- **name**: Apple solo da el nombre a la app en el primer login; mándalo entonces.
- Cada organizador solo ve sus propios eventos. Los eventos creados antes de este cambio
  (sin dueño) dejan de ser accesibles por la API.

## API del organizador
Todas requieren `Authorization: Bearer <token de sesión>`.

| Método | Ruta | Descripción |
|---|---|---|
| GET/POST | `/events` | Listar / crear evento |
| GET/DELETE | `/events/:id` | Detalle (participantes y exclusiones, nunca asignaciones) / borrar |
| PATCH | `/events/:id` | Cambiar `name` y/o `date` (solo lo enviado; `"date": null` quita la fecha). Permitido tras el sorteo |
| POST | `/events/:id/participants` | Añadir participante |
| PUT/DELETE | `/events/:id/participants/:pid` | Editar / quitar. `409` si es tutor de alguien y se intenta borrar o quitarle el teléfono |
| GET | `/events/:id/participants/:pid/wards` | Participantes que tienen a `:pid` como tutor (`guardianId`) |
| GET | `/events/:id/participants/:pid/excluded` | Participantes a los que `:pid` no puede regalar (`:pid` es `giverId` en la exclusión) |
| POST | `/events/:id/exclusions` | Excluir un par (en ambos sentidos) |
| DELETE | `/events/:id/exclusions/:xid` | Quitar exclusión |
| POST | `/events/:id/draw[?redraw=true]` | Sortear (repetir invalida enlaces). `422` si alguien no tiene teléfono ni tutor con teléfono |
| POST | `/events/:id/links` | Generar enlaces para todos |
| POST | `/events/:id/participants/:pid/link` | Generar enlace de uno |

Pública: `GET /health`, `GET /r/:token`, `POST /r/:token`.

## Desarrollo local
La imagen de vista previa de los enlaces (`/og/<evento>.png`) se dibuja con libgd, que hay que tener instalada
(en Docker la instala el `Dockerfile`):
```bash
brew install gd pkg-config
```

```bash
export APPLE_BUNDLE_ID=dev.hdvillamil.secretsanta   # y/o GOOGLE_CLIENT_ID=...
swift run App serve
swift test
```

## Despliegue en el Mac mini
Requiere OrbStack. En el servidor:
```bash
git clone <url-del-repo> ~/secret-satan-backend && cd ~/secret-satan-backend
./scripts/setup-server.sh <url-del-repo>
```
Cloudflare: Zero Trust → Networks → Tunnels → crear túnel → copiar el token (`TUNNEL_TOKEN`)
→ Public hostname `secretsanta.hdvillamil.dev` → servicio `http://api:8080`.

## Notas de seguridad
- Los tokens de los enlaces y de sesión son aleatorios de 256 bits; en la base de datos solo se guarda su hash.
- El `GET` del enlace no lo consume (las vistas previas de WhatsApp/iMessage lo quemarían); lo consume el `POST` del botón.
- La API del organizador nunca devuelve las asignaciones. Quien tenga acceso al fichero SQLite sí podría verlas.
