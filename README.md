# Secret Satan — Backend

Backend (Swift + Vapor + SQLite) de la app de amigo secreto.

## Flujo
1. El organizador crea un evento y da de alta a los participantes desde la app iOS
   (nombre, teléfono y, para los niños, el tutor que recibe su enlace).
2. `POST /events/:id/draw` hace el sorteo en el servidor (ver [Algoritmo del sorteo](#algoritmo-del-sorteo)).
3. `POST /events/:id/links` genera un enlace de un solo uso por participante; la app los
   comparte con la hoja "Compartir" de iOS (a todos o a uno).
4. Cada persona abre su enlace `https://<dominio>/r/<token>`, pulsa "Mostrar" y ve su amigo
   secreto. El enlace se consume. Si se pierde, el organizador genera uno nuevo
   (`POST /events/:id/participants/:pid/link`).

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
| GET/POST | `/events` | Listar / crear evento (`name`, `date`, `budget`, `message` opcional) |
| GET/DELETE | `/events/:id` | Detalle (participantes y exclusiones, nunca asignaciones) / borrar |
| PATCH | `/events/:id` | Cambiar `name`, `date` y/o `message` (solo lo enviado; `null` quita la fecha o el mensaje). Permitido tras el sorteo |
| POST | `/events/:id/participants` | Añadir participante (solo antes del sorteo) |
| PUT/DELETE | `/events/:id/participants/:pid` | Editar / quitar (quitar, solo antes del sorteo). `409` si es tutor de alguien y se intenta borrar o quitarle el teléfono |
| GET | `/events/:id/participants/:pid/wards` | Participantes que tienen a `:pid` como tutor (`guardianId`) |
| GET | `/events/:id/participants/:pid/excluded` | Participantes a los que `:pid` no puede regalar (`:pid` es `giverId` en la exclusión) |
| POST | `/events/:id/exclusions` | Excluir un par (en ambos sentidos) |
| DELETE | `/events/:id/exclusions/:xid` | Quitar exclusión |
| POST | `/events/:id/draw[?redraw=true]` | Sortear (repetir invalida enlaces). `422` si alguien no tiene teléfono ni tutor con teléfono, si hay menos de 3 participantes o si no existe un reparto válido |
| POST | `/events/:id/links` | Generar enlaces para todos |
| POST | `/events/:id/participants/:pid/link` | Generar enlace de uno |

`message` (máx. 500 caracteres) se muestra al pie de la web del enlace; si es `null` o vacío, la web muestra una cita de Navidad.

Pública: `GET /health`, `GET /r/:token`, `POST /r/:token`, `GET /og.png`, `GET /og/:evento.png`.

## Algoritmo del sorteo
Implementado en `Sources/App/Services/DrawService.swift`. El resultado es un reparto
`quien regala → a quien`, donde cada participante regala exactamente una vez y recibe
exactamente un regalo.

**Reglas**
1. Nadie se regala a sí mismo.
2. Se respetan las exclusiones. Una exclusión se guarda en los dos sentidos, así que A no regala a B ni B a A.
3. Un niño no regala a su tutor, porque el tutor recibe el enlace del niño y vería a quién le ha tocado.
   El tutor sí puede regalar al niño.
4. No hay regalos cruzados: si A regala a B, B no puede regalar a A. Con 2 personas el único
   reparto posible es cruzado, por eso hacen falta al menos 3 participantes.

**Pasos**
1. **Comprobaciones previas** (en el controlador): todos tienen teléfono o un tutor con teléfono,
   y hay al menos 3 participantes. Si no, `422`.
2. **Pares prohibidos**: se juntan las exclusiones y los pares niño → tutor.
3. **Candidatos**: para cada participante se calcula la lista de personas a las que puede regalar
   (reglas 1–3) y se baraja al azar.
4. **Orden**: se procesa primero a quien tiene menos candidatos. Los empates se rompen al azar.
   Así se detectan antes los callejones sin salida y el backtracking es más rápido.
5. **Backtracking**: se asigna a cada participante, en ese orden, el primer candidato que:
   - todavía no recibe regalo de nadie, y
   - no le regala ya a él (regla 4).

   Si alguien se queda sin candidatos válidos, se deshace la última asignación y se prueba el
   siguiente candidato de la persona anterior.
6. **Resultado**: si se encuentra un reparto completo, se guarda en una transacción. La
   transacción borra las asignaciones y los enlaces anteriores y marca el evento como `drawn`.
   Si no existe ningún reparto posible, se devuelve `422` y no se guarda nada.

El barajado de candidatos y del orden hace que cada sorteo dé un resultado distinto. No es
perfectamente uniforme entre todos los repartos posibles, pero es imprevisible para los participantes.

## Notas de seguridad
- Los tokens de los enlaces y de sesión son aleatorios de 256 bits; en la base de datos solo se guarda su hash.
- El `GET` del enlace no lo consume (las vistas previas de WhatsApp/iMessage lo quemarían); lo consume el `POST` del botón.
- La API del organizador nunca devuelve las asignaciones. Quien tenga acceso al fichero SQLite sí podría verlas.
