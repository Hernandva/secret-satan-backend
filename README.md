# Secret Satan — Backend

Backend (Swift + Vapor + SQLite) de la app de amigo secreto.

## Flujo
1. El organizador crea un evento y da de alta a los participantes desde la app iOS
   (nombre, teléfono, unidad familiar y, para los niños, el tutor que recibe su enlace).
2. `POST /events/:id/draw` hace el sorteo en el servidor (sin autoasignación, sin misma
   unidad familiar, respetando exclusiones).
3. `POST /events/:id/links` genera un enlace de un solo uso por participante; la app los
   comparte con la hoja "Compartir" de iOS (a todos o a uno).
4. Cada persona abre su enlace `https://secretsanta.hdvillamil.dev/r/<token>`, pulsa
   "Mostrar" y ve su amigo secreto. El enlace se consume. Si se pierde, el organizador
   genera uno nuevo (`POST /events/:id/participants/:pid/link`).

## API del organizador
Todas requieren `Authorization: Bearer <ADMIN_TOKEN>`.

| Método | Ruta | Descripción |
|---|---|---|
| GET/POST | `/events` | Listar / crear evento |
| GET/DELETE | `/events/:id` | Detalle (participantes y exclusiones, nunca asignaciones) / borrar |
| POST | `/events/:id/participants` | Añadir participante |
| PUT/DELETE | `/events/:id/participants/:pid` | Editar / quitar |
| POST | `/events/:id/exclusions` | Excluir un par (en ambos sentidos) |
| DELETE | `/events/:id/exclusions/:xid` | Quitar exclusión |
| POST | `/events/:id/draw[?redraw=true]` | Sortear (repetir invalida enlaces) |
| POST | `/events/:id/links` | Generar enlaces para todos |
| POST | `/events/:id/participants/:pid/link` | Generar enlace de uno |

Pública: `GET /health`, `GET /r/:token`, `POST /r/:token`.

## Desarrollo local
```bash
export ADMIN_TOKEN=$(openssl rand -hex 32)
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
- Los tokens de los enlaces son aleatorios de 256 bits; en la base de datos solo se guarda su hash.
- El `GET` del enlace no lo consume (las vistas previas de WhatsApp/iMessage lo quemarían); lo consume el `POST` del botón.
- La API del organizador nunca devuelve las asignaciones. Quien tenga acceso al fichero SQLite sí podría verlas.
