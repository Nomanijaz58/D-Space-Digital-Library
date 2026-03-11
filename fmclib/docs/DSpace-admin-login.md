# DSpace admin login (invalid email/password fix)

## 1. Create admin with all required options

DSpace `create-administrator` only uses the `-p` password when you also pass **-c** (language). Use:

```bash
docker exec -it dspace /dspace/bin/dspace create-administrator -e admin@example.com -f Admin -l User -c en -p admin123
```

Then log in with:
- **Email:** `admin@example.com`
- **Password:** `admin123`

---

## 2. Where you log in

- **Backend only (your current setup):**  
  `docker-compose.yml` only runs the **backend** on **port 8080**. There may be no normal “DSpace” login page at `http://localhost:8080`; that port often serves only the REST API.

- **Full DSpace 7 UI:**  
  The usual login page is the **Angular UI**, which runs on **port 4000** and must be started separately:

```bash
cd /Users/finelaptop/Downloads/DSpace-main
docker compose -f dspace/src/main/docker-compose/docker-compose-angular.yml up -d
```

Then open **http://localhost:4000** and log in with `admin@example.com` / `admin123`.

If you only start the main `docker-compose.yml`, you do **not** get the Angular UI; you only get the backend. Any “invalid username or password” might be from a different login (e.g. Tomcat or another app), not the DSpace user database.

---

## 3. Summary

| Step | Command / action |
|------|-------------------|
| 1 | `docker exec -it dspace /dspace/bin/dspace create-administrator -e admin@example.com -f Admin -l User -c en -p admin123` |
| 2 | Start Angular UI: `docker compose -f dspace/src/main/docker-compose/docker-compose-angular.yml up -d` |
| 3 | Open **http://localhost:4000** in the browser |
| 4 | Log in with **admin@example.com** / **admin123** |

If you still get “invalid email or password”, say exactly which URL you use to log in (e.g. `http://localhost:4000` or `http://localhost:8080/...`).
