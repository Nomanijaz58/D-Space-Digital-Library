# How to find your FMC collection handle

Your FMC collection handle is the persistent ID DSpace gives the collection where FMC submissions go. It looks like:

**`123456789/XX`**

- First number = repository prefix  
- Second part = collection ID  

Use this **exact** value in:
- `item-submission.xml` → `<name-map collection-handle="123456789/XX" submission-name="FMC"/>`
- `fmclib.env` → `export FMC_DEFAULT_COLLECTION="123456789/XX"`

---

## Method 1: REST API (quick)

**If DSpace backend is at `http://localhost:8080/server`:**

```bash
curl -s "http://localhost:8080/server/api/core/collections" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for c in d.get('_embedded', {}).get('collections', []):
    name = c.get('name', '?')
    handle = c.get('handle', '?')
    print(f\"  {handle}  {name}\")
"
```

If you get **401** or empty, the API may require login. Try with a session cookie or use Method 2.

**With Docker** (run inside the container or use a URL reachable from your host):

```bash
# From host (if port 8080 is mapped)
curl -s "http://localhost:8080/server/api/core/collections" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for c in d.get('_embedded', {}).get('collections', []):
    print(c.get('handle'), c.get('name'))
"
```

Pick the line whose name is your FMC collection; the first column is the handle (e.g. `123456789/4`).

---

## Method 2: DSpace Web UI

1. Open DSpace in the browser: **http://localhost:8080** (or your UI URL, e.g. **http://localhost:4000** for the Angular frontend).
2. Log in as admin.
3. Go to **Admin** → **Collections** (or **Settings** → **Collections**).
4. Open the collection you want to use for FMC.
5. On the collection’s view/edit page, find the **Handle** field. It will look like **123456789/4**.
6. Use that value as your FMC collection handle.

---

## Method 3: From Docker container (structure export)

If you use Docker and have admin e-person email:

```bash
docker exec dspace /dspace/bin/dspace structure-builder -x -e admin@example.com -o /tmp/struct.xml 2>/dev/null
docker exec dspace cat /tmp/struct.xml | grep -E 'collection|handle'
```

In the XML, find the `<collection>` element for your FMC collection; its `id` or the referenced handle is what you need. You can also open **Admin → Collections** in the UI and read the handle from there (Method 2).

---

## Set it in your environment

Once you have the handle (e.g. `123456789/4`):

**1. In `fmclib/config/fmclib.env`:**
```bash
export FMC_DEFAULT_COLLECTION="123456789/4"
```

**2. In DSpace `config/item-submission.xml`** (in `<submission-map>`):
```xml
<name-map collection-handle="123456789/4" submission-name="FMC"/>
```

**3. In the shell when running scripts:**
```bash
export FMC_DEFAULT_COLLECTION="123456789/4"
```

Use the **same** handle everywhere (no spaces; the slash is part of the handle).
