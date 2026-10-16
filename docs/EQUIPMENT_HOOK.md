# Equipment library hook

`POST /gym/api/hook/equipment` with `Authorization: Bearer <WEIGHT_HOOK_TOKEN>` (same token as the body hook, in the server's `.env`; writes to `WEIGHT_HOOK_UID`).

Upsert (matched by `id`, else by name, case-insensitive):

```json
{ "name": "坐姿推胸机", "primary": ["chest"], "secondary": ["shoulders", "arms"],
  "exercise_ids": ["0576"], "exercises": ["machine chest press"],
  "note": "QuikBody", "location": "", "photo_base64": "<optional jpeg/png/webp, base64 or data URL>" }
```

Groups: chest, back, legs, shoulders, arms, core (Chinese 胸/背/腿/肩/手臂/核心 accepted).
Delete: `{ "delete": true, "id": "eq..." }` or `{ "delete": true, "name": "..." }`.
List: `GET /gym/api/hook/equipment` with the same header.
Response: `{ ok, created, item, message }`.
