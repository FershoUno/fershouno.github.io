#!/bin/bash

OUTPUT="public"
DEBUG=false

# Enforce UTF-8
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

echo ""
echo "=============================================="
echo "  BLOGCV - Static Site Generator v3"
echo "=============================================="
echo ""

# =====================================================
# HELPERS
# =====================================================

debug() {
  $DEBUG && echo "  [DEBUG] $*"
}

warn() {
  echo "  [WARNING] $*"
}

error_out() {
  echo "  [ERROR] $*"
  exit 1
}

to_webp() {
  echo "$1" | sed 's/\.\(png\|jpg\|jpeg\|bmp\|gif\)$/.webp/i'
}

escape_js_str() {
  sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//'
}

html_esc() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
}

json_val() {
  jq . "$1" > /dev/null 2>&1
}

jq_str() {
  jq -r ".$1 // empty" "$2" 2>/dev/null
}

jq_bool() {
  jq -r ".$1 // false" "$2" 2>/dev/null
}

json_arr_enabled() {
  jq '[.[] | select(.enabled != false)] | length' "$1" 2>/dev/null || echo 0
}

# =====================================================
# VALIDATE ALL JSON FILES
# =====================================================

REQUIRED_JSON="settings.json profile.json projects.json jobs.json communities.json contacts.json"
JSON_OK=1

echo "  --- Validando archivos JSON ---"

for f in $REQUIRED_JSON; do
  if [ ! -f "assets/$f" ]; then
    echo "  [ERROR] No se encontró assets/$f"
    JSON_OK=0
  elif json_val "assets/$f"; then
    echo "  [OK] assets/$f válido"
  else
    echo "  [ERROR] JSON inválido en assets/$f"
    JSON_OK=0
  fi
done

echo ""

if [ "$JSON_OK" -eq 0 ]; then
  echo "  [ERROR] Uno o más archivos JSON son inválidos o faltan. Abortando."
  exit 1
fi

# =====================================================
# READ SETTINGS
# =====================================================

echo "  [INFO] Cargando settings.json"

THEME=$(jq_str theme assets/settings.json)
SITE_TITLE=$(jq_str site_title assets/settings.json)
SITE_DESC=$(jq_str site_description assets/settings.json)
LONG_DESC=$(jq_str long_description assets/settings.json)
FULLNAME=$(jq_str fullname assets/settings.json)
USERNAME=$(jq_str username assets/settings.json)
USERNAME_TITLE=$(jq_str username_title assets/settings.json)
PROF_TITLE=$(jq_str professional_title assets/settings.json)
PROFILE_IMG=$(jq_str profile_image assets/settings.json)
FAVICON=$(jq_str favicon assets/settings.json)
LANG=$(jq_str lang assets/settings.json)
LOCALE=$(jq_str locale assets/settings.json)
COPYRIGHT=$(jq_str copyright assets/settings.json)
SEO_KW=$(jq_str seo_keywords assets/settings.json)
SITE_URL=$(jq_str site_url assets/settings.json)
MOUSE_GLOW=$(jq_bool mouse_glow assets/settings.json)
PPAGE=$(jq_str posts_per_page assets/settings.json)
SHOW_RESUME=$(jq_bool show_resume assets/settings.json)
SHOW_PROJECTS=$(jq_bool show_projects assets/settings.json)
SHOW_JOBS=$(jq_bool show_jobs assets/settings.json)
SHOW_COMMUNITIES=$(jq_bool show_communities assets/settings.json)
SHOW_CONTACT=$(jq_bool show_contact assets/settings.json)
#SHOW_BLOG=$(jq_bool show_blog assets/settings.json)
COMPRESS_VIDEO=$(jq_bool compress_video assets/settings.json)

[ -z "$LONG_DESC" ] && LONG_DESC="$SITE_DESC"
[ -z "$SITE_URL" ] && SITE_URL="https://${USERNAME}.github.io/"
SITE_URL="${SITE_URL%/}/"
[ -z "$PPAGE" ] && PPAGE=5

PROFILE_WEBP=$(to_webp "$PROFILE_IMG")
FAVICON_WEBP=$(to_webp "$FAVICON")

echo "  Author:   ${FULLNAME}"
echo "  Title:    ${SITE_TITLE}"
echo "  Theme:    ${THEME}"
echo "  URL:      ${SITE_URL}"
echo ""

# =====================================================
# COUNT DATA
# =====================================================

TOTAL_COMMUNITIES=$(json_arr_enabled assets/communities.json)
TOTAL_JOBS=$(json_arr_enabled assets/jobs.json)
TOTAL_PROJECTS=$(json_arr_enabled assets/projects.json)
TOTAL_CONTACTS=$(jq '[.social[] | select(.enabled != false and .url != "")] | length' assets/contacts.json 2>/dev/null || echo 0)
POST_FILES=(assets/posts/*.md)
TOTAL_POSTS=0
for pf in "${POST_FILES[@]}"; do
  [ -f "$pf" ] && TOTAL_POSTS=$((TOTAL_POSTS + 1))
done

# Count total activities across all communities
TOTAL_ACTIVITIES=$(jq '[.[] | select(.enabled != false) | .activities // [] | length] | add' assets/communities.json 2>/dev/null || echo 0)

# =====================================================
# INSPECT JSON STRUCTURES
# =====================================================

echo "  [INFO] Leyendo communities.json"
DEBUG_COMM_COUNT=$(jq '[.[] | select(.enabled != false)] | length' assets/communities.json)
DEBUG_COMM_ACT=$(jq '[.[] | select(.enabled != false) | .activities // [] | length] | add' assets/communities.json)
echo "  [INFO] Comunidades encontradas: ${DEBUG_COMM_COUNT}"
echo "  [INFO] Actividades encontradas: ${DEBUG_COMM_ACT:-0}"
if [ "$DEBUG_COMM_COUNT" -eq 0 ] 2>/dev/null; then
  echo "  [WARNING] No se encontraron comunidades válidas"
fi
debug "Estructura communities: $(jq '.[0] | keys' assets/communities.json)"

echo "  [INFO] Leyendo jobs.json"
DEBUG_JOB_COUNT=$(jq '[.[] | select(.enabled != false)] | length' assets/jobs.json)
DEBUG_JOB_RESP=$(jq '[.[] | select(.enabled != false) | .responsibilities // [] | length] | add' assets/jobs.json)
DEBUG_JOB_ACH=$(jq '[.[] | select(.enabled != false) | .achievements // [] | length] | add' assets/jobs.json)
echo "  [INFO] Experiencias encontradas: ${DEBUG_JOB_COUNT}"
echo "  [INFO] Responsabilidades encontradas: ${DEBUG_JOB_RESP:-0}"
echo "  [INFO] Logros encontrados: ${DEBUG_JOB_ACH:-0}"
debug "Estructura jobs: $(jq '.[0] | keys' assets/jobs.json)"

# =====================================================
# RESOURCE VALIDATION
# =====================================================

WARN_COUNT=0
ERR_COUNT=0

validate_resources() {
  echo "  [INFO] Validando recursos..."

  # Validate referenced images exist
  local img_error=0
  for img_ref in $(jq -r '.[] | select(.enabled != false) | .image // empty' assets/projects.json 2>/dev/null); do
    if [ -n "$img_ref" ] && [ ! -f "assets/images/$img_ref" ] && [ ! -f "assets/images/$(to_webp "$img_ref")" ]; then
      warn "Imagen no encontrada: $img_ref"
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
  done
  for img_ref in $(jq -r '.[] | select(.enabled != false) | .logo // empty' assets/communities.json 2>/dev/null); do
    if [ -n "$img_ref" ] && [ ! -f "assets/images/$img_ref" ]; then
      warn "Logo no encontrado: $img_ref"
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
  done

  # Validate posts
  for post in assets/posts/*.md; do
    [ -f "$post" ] || continue
    local has_title=false
    local has_date=false
    if head -1 "$post" | grep -q '^---$'; then
      local pt=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="title"{print 1}' "$post")
      local pd=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="date"{print 1}' "$post")
      [ -n "$pt" ] && has_title=true
      [ -n "$pd" ] && has_date=true
    fi
    if ! $has_title; then
      local fallback=$(grep '^# ' "$post" | head -1)
      [ -n "$fallback" ] && has_title=true
    fi
    if ! $has_title; then
      warn "Post $(basename "$post") no tiene titulo"
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
    if ! $has_date; then
      local fname=$(basename "$post" .md)
      if ! echo "$fname" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
        warn "Post $(basename "$post") no tiene fecha"
        WARN_COUNT=$((WARN_COUNT + 1))
      fi
    fi
  done

  echo "  [OK] Validacion de recursos completada"
}

validate_resources

# =====================================================
# CLEAN & CREATE DIRECTORIES
# =====================================================

#rm -rf "$OUTPUT" .github/workflows
mkdir -p "$OUTPUT"/{css,js,img,video,post}

# =====================================================
# GENERATE index.html
# =====================================================

exec 3>"$OUTPUT/index.html"

cat >&3 << EOF
<!DOCTYPE html>
<html lang="${LANG}" data-theme="${THEME}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${SITE_TITLE}</title>
  <meta name="description" content="${SITE_DESC}">
  <meta name="keywords" content="${SEO_KW}">
  <meta name="author" content="${FULLNAME}">

  <meta property="og:title" content="${SITE_TITLE}">
  <meta property="og:description" content="${SITE_DESC}">
  <meta property="og:image" content="${SITE_URL}img/${PROFILE_WEBP}">
  <meta property="og:url" content="${SITE_URL}">
  <meta property="og:type" content="website">
  <meta property="og:locale" content="${LOCALE}">

  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${SITE_TITLE}">
  <meta name="twitter:description" content="${SITE_DESC}">
  <meta name="twitter:image" content="${SITE_URL}img/${PROFILE_WEBP}">

  <link rel="icon" type="image/webp" href="img/${FAVICON_WEBP}">
  <link rel="canonical" href="${SITE_URL}">

  <script src="https://cdn.tailwindcss.com"></script>
  <link href="https://cdn.jsdelivr.net/npm/daisyui@4.12.14/dist/full.min.css" rel="stylesheet" type="text/css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.6.0/css/all.min.css">
  <link rel="stylesheet" href="css/main.css">

  <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>

  <script>
EOF

# ---- Embed JSON data as JS globals ----
echo "const BLOGCV_SETTINGS = $(cat assets/settings.json);" >&3
echo "const BLOGCV_PROFILE = $(cat assets/profile.json);" >&3
echo "const BLOGCV_PROJECTS = $(cat assets/projects.json);" >&3
echo "const BLOGCV_JOBS = $(cat assets/jobs.json);" >&3
echo "const BLOGCV_COMMUNITIES = $(cat assets/communities.json);" >&3
echo "const BLOGCV_CONTACTS = $(cat assets/contacts.json);" >&3

echo "const BLOGCV_POSTS = [" >&3
FIRST=true
for post in assets/posts/*.md; do
  [ -f "$post" ] || continue
  $FIRST || echo "," >&3
  FIRST=false
  filename=$(basename "$post" .md)
  slug="$filename"
  title=""; date=""; category=""; tags=""; image=""
  if head -1 "$post" | grep -q '^---$'; then
    title=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="title"{sub(/^[^:]*: /,"");print}' "$post")
    date=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="date"{sub(/^[^:]*: /,"");print}' "$post")
    category=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="category"{sub(/^[^:]*: /,"");print}' "$post")
    tags=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="tags"{sub(/^[^:]*: /,"");print}' "$post")
    image=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="image"{sub(/^[^:]*: /,"");print}' "$post")
  fi
  [ -z "$title" ] && title=$(grep '^# ' "$post" | head -1 | sed 's/^# //')
  [ -z "$date" ] && echo "$filename" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' && date=$(echo "$filename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')
  content=$(awk 'BEGIN{c=0} /^---$/{c++;next} c>=2{print}' "$post" 2>/dev/null | escape_js_str)
  [ -z "$content" ] && content=$(cat "$post" | escape_js_str)
  e_title=$(echo "$title" | sed 's/"/\\"/g')
  e_cat=$(echo "$category" | sed 's/"/\\"/g')
  e_tags=$(echo "$tags" | sed 's/"/\\"/g')
  e_image=$(echo "$image" | sed 's/"/\\"/g')
  echo -n '{"slug":"'"$slug"'","title":"'"$e_title"'","date":"'"$date"'","category":"'"$e_cat"'","tags":"'"$e_tags"'","image":"'"$e_image"'","content":"'"$content"'"}' >&3
done
echo "];" >&3

cat >&3 << 'ENDSCRIPT'
  </script>
</head>
<body>
  <div id="app" class="min-h-screen">
ENDSCRIPT

# =====================================================
# GENERATE NAVBAR
# =====================================================

build_navbar() {
  local items=""
  if [ "$SHOW_RESUME" != "false" ]; then
    items="${items}<li><a href=\"#resume\">CV</a></li>"
  fi
  if [ "$SHOW_PROJECTS" != "false" ] && [ "$TOTAL_PROJECTS" -gt 0 ]; then
    items="${items}<li><a href=\"#projects\">Proyectos</a></li>"
  fi
  if [ "$SHOW_COMMUNITIES" != "false" ] && [ "$TOTAL_COMMUNITIES" -gt 0 ]; then
    items="${items}<li><a href=\"#communities\">Comunidades</a></li>"
  fi
  if [ "$SHOW_JOBS" != "false" ] && [ "$TOTAL_JOBS" -gt 0 ]; then
    items="${items}<li><a href=\"#jobs\">Experiencia</a></li>"
  fi
  if [ "$SHOW_CONTACT" != "false" ] && [ "$TOTAL_CONTACTS" -gt 0 ]; then
    items="${items}<li><a href=\"#contact\">Contacto</a></li>"
  fi
  if [ "$TOTAL_POSTS" -gt 0 ]; then
    items="${items}<li><a href=\"#blog\">Blog</a></li>"
  fi

  cat >&3 << NAVEOF
  <nav class="navbar bg-base-100/90 backdrop-blur-md shadow-sm sticky top-0 z-50 transition-all duration-300" role="navigation" aria-label="Navegación principal">
    <div class="navbar-start">
      <div class="dropdown">
        <div tabindex="0" role="button" class="btn btn-ghost lg:hidden" aria-label="Menú">
          <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h8m-8 6h16"/>
          </svg>
        </div>
        <ul tabindex="0" class="menu menu-sm dropdown-content mt-3 z-[1] p-2 shadow bg-base-100 rounded-box w-52">
          ${items}
        </ul>
      </div>
      <a class="btn btn-ghost text-lg md:text-xl" href="#hero" aria-label="Inicio">${SITE_TITLE}</a>
    </div>
    <div class="navbar-center hidden lg:flex"><ul class="menu menu-horizontal px-1">${items}</ul></div>
    <div class="navbar-end">
      <a class="btn btn-primary" href="#contact">Contactar</a>
    </div>
  </nav>
NAVEOF
}

build_navbar

echo "<main>" >&3

# =====================================================
# GENERATE HERO
# =====================================================

build_hero() {
  local img=""
  [ -n "$PROFILE_IMG" ] && img="<div class=\"fade-in-scale\"><img src=\"img/${PROFILE_WEBP}\" class=\"max-w-sm rounded-full shadow-2xl w-64 h-64 object-cover border-4 border-primary\" alt=\"${FULLNAME}\" loading=\"lazy\" width=\"256\" height=\"256\"/></div>"

  local desc="${LONG_DESC:-$SITE_DESC}"

  cat >&3 << HEROEOF
  <section id="hero" class="hero min-h-[calc(100vh-4rem)] bg-base-200" aria-label="Presentación">
    <div class="hero-content flex-col lg:flex-row-reverse gap-12">
      ${img}
      <div class="max-w-xl">
        <h1 class="text-5xl font-bold fade-in">${FULLNAME}</h1>
        <p class="text-2xl text-primary font-semibold mt-2 fade-in">${PROF_TITLE}</p>
        <p class="py-6 text-lg leading-relaxed fade-in">${desc}</p>
        <div class="flex flex-wrap gap-4 fade-in">
          <a href="#resume" class="btn btn-primary">Ver CV</a>
          <a href="#projects" class="btn btn-outline">Proyectos</a>
          <a href="#contact" class="btn btn-outline">Contacto</a>
        </div>
      </div>
    </div>
  </section>
HEROEOF
}

build_hero

# =====================================================
# GENERATE RESUME
# =====================================================

build_resume() {
  if [ "$SHOW_RESUME" = "false" ]; then
    echo "  [INFO] Sección CV deshabilitada en settings.json"
    return
  fi

  local summary=$(jq_str summary assets/profile.json | html_esc)
  local has_content=0

  echo "  [INFO] Generando sección CV"

  cat >&3 << 'RESUMEEOF'
  <section id="resume" class="py-20 px-4 bg-base-100" aria-label="Curriculum">
    <div class="max-w-5xl mx-auto">
      <h2 class="text-3xl font-bold mb-8 text-center fade-in">Curriculum</h2>
RESUMEEOF

  if [ -n "$summary" ]; then
    has_content=1
    echo "      <div class=\"card bg-base-200 shadow-xl mb-8 fade-in\"><div class=\"card-body\"><h3 class=\"card-title text-xl\">Resumen</h3><p class=\"text-base leading-relaxed mt-2\">${summary}</p></div></div>" >&3
  fi

  echo "      <div class=\"grid md:grid-cols-2 gap-6 mb-8\">" >&3

  # Skills
  local skills_html=$(jq -r '.skills // [] | map("<span class=\"badge badge-primary badge-lg\">" + . + "</span>") | join(" ")' assets/profile.json 2>/dev/null)
  if [ -n "$skills_html" ]; then
    has_content=1
    echo "        <div class=\"card bg-base-200 shadow-xl fade-in\"><div class=\"card-body\"><h3 class=\"card-title text-xl\">Habilidades Técnicas</h3><div class=\"flex flex-wrap gap-2 mt-4\">${skills_html}</div></div></div>" >&3
  fi

  # Specialties
  local specs_html=$(jq -r '.specialties // [] | map("<li class=\"flex items-center gap-2\"><svg class=\"w-4 h-4 text-primary shrink-0\" fill=\"none\" viewBox=\"0 0 24 24\" stroke=\"currentColor\"><path stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"2\" d=\"M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z\"/></svg><span>" + . + "</span></li>") | join("")' assets/profile.json 2>/dev/null)
  if [ -n "$specs_html" ]; then
    has_content=1
    echo "        <div class=\"card bg-base-200 shadow-xl fade-in\"><div class=\"card-body\"><h3 class=\"card-title text-xl\">Especialidades</h3><ul class=\"mt-4 space-y-2\">${specs_html}</ul></div></div>" >&3
  fi

  echo "      </div>" >&3

  # Certifications
  local certs_html=$(jq -r '.certifications // [] | map("<span class=\"badge badge-outline badge-lg\">" + . + "</span>") | join(" ")' assets/profile.json 2>/dev/null)
  if [ -n "$certs_html" ]; then
    has_content=1
    echo "      <div class=\"card bg-base-200 shadow-xl fade-in\"><div class=\"card-body\"><h3 class=\"card-title text-xl\">Certificaciones</h3><div class=\"flex flex-wrap gap-2 mt-4\">${certs_html}</div></div></div>" >&3
  fi

  echo "    </div>" >&3
  echo "  </section>" >&3

  if [ "$has_content" -eq 1 ]; then
    echo "  [OK] Sección CV generada"
  else
    echo "  [WARNING] Sección CV sin contenido"
  fi
}

build_resume

# =====================================================
# GENERATE PROJECTS
# =====================================================

build_projects() {
  if [ "$SHOW_PROJECTS" = "false" ]; then
    echo "  [INFO] Sección Proyectos deshabilitada en settings.json"
    return
  fi

  local count=$(jq '[.[] | select(.enabled != false)] | length' assets/projects.json)
  if [ "$count" -eq 0 ]; then
    echo "  [WARNING] No se encontraron proyectos habilitados"
    return
  fi

  echo "  [INFO] Generando sección Proyectos (${count} proyectos)"

  cat >&3 << 'PROJEOF'
  <section id="projects" class="py-20 px-4 bg-base-200" aria-label="Proyectos">
    <div class="max-w-5xl mx-auto">
      <h2 class="text-3xl font-bold mb-8 text-center fade-in">Proyectos</h2>
      <div class="grid md:grid-cols-2 lg:grid-cols-3 gap-6">
PROJEOF

  jq -c '.[] | select(.enabled != false)' assets/projects.json | while read -r p; do
    p_title=$(echo "$p" | jq -r '.title // ""' | html_esc)
    p_year=$(echo "$p" | jq -r '.year // ""' | html_esc)
    p_desc=$(echo "$p" | jq -r '.description // ""' | html_esc)
    p_image=$(echo "$p" | jq -r '.image // ""')
    p_github=$(echo "$p" | jq -r '.github // ""' | html_esc)
    p_website=$(echo "$p" | jq -r '.website // ""' | html_esc)
    p_img_webp=$(to_webp "$p_image")

    local img_html=""
    if [ -n "$p_image" ]; then
      img_html="<figure><button type=\"button\" class=\"project-img-btn\" data-full=\"img/${p_img_webp}\" data-alt=\"${p_title}\" aria-label=\"Ampliar imagen: ${p_title}\"><img src=\"img/${p_img_webp}\" alt=\"${p_title}\" class=\"w-full h-48 object-cover\" loading=\"lazy\" decoding=\"async\"/></button></figure>"
    fi

    local gh_html=""
    [ -n "$p_github" ] && gh_html="<a href=\"${p_github}\" target=\"_blank\" rel=\"noopener\" class=\"btn btn-ghost btn-sm\" aria-label=\"Código fuente\"><i class=\"fa-brands fa-github text-lg\"></i></a>"

    local ws_html=""
    [ -n "$p_website" ] && ws_html="<a href=\"${p_website}\" target=\"_blank\" rel=\"noopener\" class=\"btn btn-primary btn-sm\" aria-label=\"Sitio web\"><i class=\"fa-solid fa-globe\"></i> Sitio</a>"

    local year_badge=""
    [ -n "$p_year" ] && year_badge="<span class=\"badge badge-primary\">${p_year}</span>"

    cat >&3 << PROJCARD
        <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-all duration-300 fade-in">
          ${img_html}
          <div class="card-body">
            <div class="flex justify-between items-start gap-2"><h3 class="card-title">${p_title}</h3>${year_badge}</div>
            <p class="text-sm mt-2">${p_desc}</p>
            <div class="card-actions justify-end mt-4">${gh_html}${ws_html}</div>
          </div>
        </div>
PROJCARD
  done

  echo "      </div>" >&3
  echo "    </div>" >&3
  echo "  </section>" >&3

  echo "  [OK] Sección Proyectos generada (${count} proyectos)"
}

build_projects

# =====================================================
# GENERATE COMMUNITIES (TWO LEVEL)
# =====================================================

build_communities() {
  if [ "$SHOW_COMMUNITIES" = "false" ]; then
    echo "  [INFO] Sección Comunidades deshabilitada en settings.json"
    return
  fi

  local count=$(jq '[.[] | select(.enabled != false)] | length' assets/communities.json)
  if [ "$count" -eq 0 ]; then
    echo "  [WARNING] No se encontraron comunidades habilitadas"
    return
  fi

  echo "  [INFO] Generando sección Comunidades (${count} comunidades, ${TOTAL_ACTIVITIES} actividades)"

  cat >&3 << 'COMMEOF'
  <section id="communities" class="py-20 px-4 bg-base-100" aria-label="Comunidades">
    <div class="max-w-6xl mx-auto">
      <h2 class="text-3xl font-bold mb-8 text-center fade-in">Comunidades</h2>
      <p class="text-center opacity-70 mb-10 max-w-2xl mx-auto fade-in">Selecciona una comunidad para ver tu participación y las actividades que realizaste.</p>
      <div id="communities-container" class="fade-in">
        <div class="hist">
          <div id="communities-list" class="hist-list" role="tablist" aria-label="Comunidades" aria-orientation="vertical"></div>
          <div class="hist-main">
            <div id="communities-detail" class="hist-detail" role="tabpanel" tabindex="0" aria-live="polite"></div>
          </div>
        </div>
      </div>
    </div>
  </section>
COMMEOF

  echo "  [OK] Sección Comunidades generada (${count} comunidades)"
}

build_communities

# =====================================================
# GENERATE JOBS (TWO LEVEL)
# =====================================================

build_jobs() {
  if [ "$SHOW_JOBS" = "false" ]; then
    echo "  [INFO] Sección Experiencia deshabilitada en settings.json"
    return
  fi

  local count=$(jq '[.[] | select(.enabled != false)] | length' assets/jobs.json)
  if [ "$count" -eq 0 ]; then
    echo "  [WARNING] No se encontraron experiencias laborales habilitadas"
    return
  fi

  echo "  [INFO] Generando sección Experiencia (${count} trabajos)"

  cat >&3 << JOBSEOF
  <section id="jobs" class="py-20 px-4 bg-base-200" aria-label="Experiencia laboral">
    <div class="max-w-6xl mx-auto">
      <h2 class="text-3xl font-bold mb-8 text-center fade-in">Experiencia Laboral</h2>
      <p class="text-center opacity-70 mb-10 max-w-2xl mx-auto fade-in">Recorre tu trayectoria: selecciona una posición para ver sus detalles.</p>
      <div id="jobs-container" class="fade-in">
        <div class="hist">
          <div id="jobs-list" class="hist-list" role="tablist" aria-label="Experiencia laboral" aria-orientation="vertical"></div>
          <div class="hist-main">
            <div id="jobs-detail" class="hist-detail" role="tabpanel" tabindex="0" aria-live="polite"></div>
          </div>
        </div>
      </div>
    </div>
  </section>
JOBSEOF

  echo "  [OK] Sección Experiencia generada (${count} trabajos)"
}

build_jobs

# =====================================================
# GENERATE CONTACT
# =====================================================

build_contact() {
  if [ "$SHOW_CONTACT" = "false" ]; then
    echo "  [INFO] Sección Contacto deshabilitada en settings.json"
    return
  fi

  local count=$(jq '[.social[] | select(.enabled != false and .url != "")] | length' assets/contacts.json)
  if [ "$count" -eq 0 ]; then
    echo "  [WARNING] No se encontraron contactos habilitados"
    return
  fi

  echo "  [INFO] Generando sección Contacto (${count} redes sociales)"

  local msg=$(jq -r '.message // ""' assets/contacts.json | html_esc)

  cat >&3 << CTCEOF
  <section id="contact" class="py-20 px-4 bg-base-100" aria-label="Contacto">
    <div class="max-w-4xl mx-auto">
      <h2 class="text-3xl font-bold mb-8 text-center fade-in">Contacto</h2>
CTCEOF

  if [ -n "$msg" ]; then
    cat >&3 << CTCMSG
      <div class="card bg-base-200 shadow-xl mb-10 max-w-2xl mx-auto fade-in"><div class="card-body text-center"><p class="text-lg leading-relaxed">${msg}</p></div></div>
CTCMSG
  fi

  echo "      <div class=\"grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4 max-w-3xl mx-auto\">" >&3

  local ICONS='{"telegram":"fa-brands fa-telegram","github":"fa-brands fa-github","instagram":"fa-brands fa-instagram","whatsapp":"fa-brands fa-whatsapp","facebook":"fa-brands fa-facebook","tiktok":"fa-brands fa-tiktok","linkedin":"fa-brands fa-linkedin","twitter":"fa-brands fa-twitter","youtube":"fa-brands fa-youtube","email":"fa-solid fa-envelope","website":"fa-solid fa-globe","x-twitter":"fa-brands fa-x-twitter","mastodon":"fa-brands fa-mastodon","discord":"fa-brands fa-discord","matrix":"fa-solid fa-comment","peertube":"fa-brands fa-peerlist","link":"fa-solid fa-link"}'

  jq -c '.social[] | select(.enabled != false and .url != "")' assets/contacts.json | while read -r s; do
    s_name=$(echo "$s" | jq -r '.name // ""' | html_esc)
    s_icon=$(echo "$s" | jq -r '.icon // "link"' | html_esc)
    s_url=$(echo "$s" | jq -r '.url // ""' | html_esc)

    local icon_class=$(echo "$ICONS" | jq -r ".[\"${s_icon}\"] // \"fa-solid fa-link\"")

    cat >&3 << CTCITEM
        <a href="${s_url}" target="_blank" rel="noopener noreferrer" class="card bg-base-200 shadow-lg hover:shadow-xl transition-all duration-300 hover:-translate-y-1 cursor-pointer fade-in card-glow" aria-label="${s_name}">
          <div class="card-body items-center text-center p-6">
            <i class="${icon_class} text-3xl text-primary mb-2"></i>
            <span class="text-sm font-semibold">${s_name}</span>
          </div>
        </a>
CTCITEM
  done

  echo "      </div>" >&3
  echo "    </div>" >&3
  echo "  </section>" >&3

  echo "  [OK] Sección Contacto generada (${count} redes sociales)"
}

build_contact

# =====================================================
# GENERATE BLOG
# =====================================================

build_blog() {
  if [ "$TOTAL_POSTS" -eq 0 ]; then
    echo "  [WARNING] No se encontraron publicaciones Markdown en assets/posts/"
    return
  fi

  echo "  [INFO] Generando sección Blog (${TOTAL_POSTS} publicaciones)"

  cat >&3 << BLOGEOF
  <section id="blog" class="py-20 px-4 bg-base-200" aria-label="Blog">
    <div class="max-w-4xl mx-auto">
      <h2 class="text-3xl font-bold mb-8 text-center fade-in">Blog</h2>

      <div class="form-control mb-8 max-w-md mx-auto fade-in">
        <div class="input-group input-group-lg">
          <input id="blog-search" type="search" placeholder="Buscar artículos..." class="input input-bordered w-full" aria-label="Buscar en el blog" />
          <span class="btn btn-square btn-ghost"><i class="fa-solid fa-search"></i></span>
        </div>
      </div>

      <p class="text-center text-sm opacity-60 mb-8 fade-in">${TOTAL_POSTS} artículo$([ "$TOTAL_POSTS" -ne 1 ] && echo "s") publicados</p>

      <div id="blog-posts">
BLOGEOF

  # Pre-render first page of posts
  local shown=0
  for post in assets/posts/*.md; do
    [ -f "$post" ] || continue
    [ "$shown" -ge "$PPAGE" ] && break

    local filename=$(basename "$post" .md)
    local slug="$filename"
    local title=""; local date=""; local category=""; local tags=""; local image=""
    local summary=""

    if head -1 "$post" | grep -q '^---$'; then
      title=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="title"{sub(/^[^:]*: /,"");print}' "$post")
      date=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="date"{sub(/^[^:]*: /,"");print}' "$post")
      category=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="category"{sub(/^[^:]*: /,"");print}' "$post")
      tags=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="tags"{sub(/^[^:]*: /,"");print}' "$post")
      image=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="image"{sub(/^[^:]*: /,"");print}' "$post")
      summary=$(awk 'BEGIN{c=0} /^---$/{c++;next} c>=2{print}' "$post" 2>/dev/null | head -c 200 | sed 's/#[^ ]* //g; s/\*\*//g; s/\*//g; s/`//g' | head -1)
    fi

    [ -z "$title" ] && title=$(grep '^# ' "$post" | head -1 | sed 's/^# //')
    [ -z "$date" ] && echo "$filename" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' && date=$(echo "$filename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')

    local e_title=$(echo "$title" | html_esc)
    local e_cat=$(echo "$category" | html_esc)
    local e_tags_html=""
    [ -n "$tags" ] && e_tags_html=$(echo "$tags" | sed 's/, */<\/span><span class="badge badge-ghost badge-xs">/g; s/^/<span class="badge badge-ghost badge-xs">/; s/$/<\/span>/')
    local summary_esc=$(echo "$summary" | html_esc)
    local reading_time="1 min"
    if [ -n "$summary" ]; then
      local wc=$(echo "$summary" | wc -w)
      [ "$wc" -gt 0 ] && reading_time="$(( (wc + 199) / 200 )) min de lectura"
    fi

    local cat_badge=""
    [ -n "$category" ] && cat_badge="<span class=\"badge badge-primary badge-sm\">${e_cat}</span>"
    local date_span=""
    [ -n "$date" ] && date_span="<span class=\"text-xs opacity-70 font-mono\">${date}</span>"

    cat >&3 << POSTCARD
        <div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-all duration-300 fade-in blog-card">
          <div class="card-body">
            <div class="flex flex-wrap gap-2 items-center mb-1">${cat_badge}${date_span}</div>
            <h3 class="card-title text-lg">${e_title}</h3>
            <div class="flex flex-wrap gap-1">${e_tags_html}</div>
            <p class="text-sm mt-2 opacity-80">${summary_esc}...</p>
            <div class="card-actions justify-between items-center mt-4">
              <span class="text-xs opacity-60">${reading_time}</span>
              <a href="#!post/${slug}" class="btn btn-primary btn-sm">Leer más</a>
            </div>
          </div>
        </div>
POSTCARD
    shown=$((shown + 1))
  done

  # Load more button if there are more posts
  if [ "$TOTAL_POSTS" -gt "$PPAGE" ]; then
    local remaining=$((TOTAL_POSTS - PPAGE))
    cat >&3 << LOADMORE
        <div class="text-center mt-10">
          <button class="btn btn-outline load-more-btn" data-remaining="${remaining}">Cargar más artículos (${remaining} restantes)</button>
        </div>
LOADMORE
  fi

  echo "      </div>" >&3
  echo "    </div>" >&3
  echo "  </section>" >&3

  echo "  [OK] Sección Blog generada (${TOTAL_POSTS} publicaciones)"
}

build_blog

echo "</main>" >&3

# =====================================================
# GENERATE FOOTER
# =====================================================

build_footer() {
  local year=$(date +%Y)
  local footer_links="<a href=\"#hero\" class=\"link link-hover text-sm\">Inicio</a>"
  [ "$SHOW_RESUME" != "false" ] && footer_links="${footer_links}<a href=\"#resume\" class=\"link link-hover text-sm\">CV</a>"
  [ "$SHOW_PROJECTS" != "false" ] && [ "$TOTAL_PROJECTS" -gt 0 ] && footer_links="${footer_links}<a href=\"#projects\" class=\"link link-hover text-sm\">Proyectos</a>"
  [ "$TOTAL_POSTS" -gt 0 ] && footer_links="${footer_links}<a href=\"#blog\" class=\"link link-hover text-sm\">Blog</a>"
  [ "$SHOW_CONTACT" != "false" ] && [ "$TOTAL_CONTACTS" -gt 0 ] && footer_links="${footer_links}<a href=\"#contact\" class=\"link link-hover text-sm\">Contacto</a>"

  cat >&3 << FOOTEOF
  <footer class="footer footer-center p-6 bg-base-300 text-base-content" role="contentinfo">
    <nav class="flex gap-4">${footer_links}</nav>
    <aside><p class="text-sm">&copy; ${year} ${USERNAME_TITLE}. ${COPYRIGHT}</p></aside>
  </footer>
FOOTEOF
}

build_footer

echo "  </div>" >&3
echo "  <script src=\"js/app.js\"></script>" >&3
echo "</body>" >&3
echo "</html>" >&3

exec 3>&-

echo "  [OK] index.html generado"
echo ""

# =====================================================
# GENERATE main.css
# =====================================================

cat > "$OUTPUT/css/main.css" << 'EOCSS'
/* === THEME TRANSITION === */
html {
  transition: background-color 0.3s ease;
}

/* === THEME TOGGLE FLOATING === */
#theme-toggle {
  position: fixed;
  bottom: 1.5rem;
  left: 1.5rem;
  z-index: 9999;
  width: 3.25rem;
  height: 3.25rem;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--fallback-b1, oklch(var(--b1)));
  color: var(--fallback-bc, oklch(var(--bc)));
  border: 1px solid var(--fallback-b2, oklch(var(--b2)));
  box-shadow: 0 4px 12px rgba(0,0,0,0.12);
  cursor: pointer;
  transition: all 0.3s ease;
  font-size: 1.35rem;
}
#theme-toggle:hover {
  transform: scale(1.1);
  color: var(--fallback-p, oklch(var(--p)));
  border-color: var(--fallback-p, oklch(var(--p)));
  box-shadow: 0 6px 20px rgba(0,0,0,0.18);
}
#theme-toggle:active {
  transform: scale(0.95);
}
#theme-toggle:focus-visible {
  outline: 2px solid var(--fallback-p, oklch(var(--p)));
  outline-offset: 3px;
}

@media (max-width: 640px) {
  #theme-toggle {
    bottom: 1rem;
    left: 1rem;
    width: 2.75rem;
    height: 2.75rem;
    font-size: 1.15rem;
  }
}

/* === CERTIFICATIONS RESPONSIVE === */
.badge-outline {
  white-space: normal;
  word-break: break-word;
  height: auto;
  min-height: 1.75rem;
}

/* === TARGET SIZE MINIMUM (WCAG 2.5.8) === */
/* Los links de texto del footer miden 20px de alto; se amplía el area
   pulsable con padding y margen negativo para no alterar la composición. */
footer .link {
  display: inline-flex;
  align-items: center;
  min-height: 1.5rem;
  padding-top: 0.25rem;
  padding-bottom: 0.25rem;
  margin-top: -0.25rem;
  margin-bottom: -0.25rem;
}

/* === PROJECT IMAGE ZOOM TRIGGER === */
.project-img-btn {
  display: block;
  width: 100%;
  cursor: zoom-in;
  overflow: hidden;
  background: none;
  border: 0;
  padding: 0;
  -webkit-tap-highlight-color: transparent;
}
.project-img-btn img {
  transition: transform 0.45s cubic-bezier(0.25, 0.46, 0.45, 0.94), opacity 0.3s ease;
}
@media (hover: hover) {
  .project-img-btn:hover img { transform: scale(1.045); }
}
.project-img-btn:focus-visible {
  outline: 2px solid var(--fallback-p, oklch(var(--p)));
  outline-offset: -2px;
  border-radius: 0.5rem;
}

/* === IMAGE LIGHTBOX ===
   Interaccion unica: clic/tap sobre la imagen abre, clic/tap sobre la imagen
   cierra. Sin boton de cierre, lupa, barra de herramientas ni caption.
   ESC queda como atajo de accesibilidad, sin ningun elemento en pantalla.

   Rendimiento: el ajuste de tamano lo resuelve el CSS (max-width/max-height)
   y la animacion solo escribe transform y opacity, que se ejecutan en la GPU
   sin provocar layout. No hay medidas por JS ni reflows forzados. */
.lightbox {
  position: fixed;
  inset: 0;
  z-index: 10000;
  display: flex;
  align-items: center;
  justify-content: center;
  /* Fondo opaco a proposito: sin backdrop-filter, que repintaria la pantalla
     completa en cada frame y es la causa mas pesada de una apertura lenta. */
  background: rgba(0, 0, 0, 0.92);
  opacity: 0;
  visibility: hidden;
  pointer-events: none;
}
.lightbox.open { opacity: 1; visibility: visible; pointer-events: auto; }

.lightbox-stage {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  cursor: zoom-out;
}

.lightbox-img {
  position: absolute;
  top: 50%;
  left: 50%;
  /* El navegador decide el tamano: siempre visible, centrada y sin deformar.
     Al no tocar width/height desde JS, abrir y cerrar no provoca layout. */
  max-width: 90vw;
  max-height: 90vh;
  width: auto;
  height: auto;
  border-radius: 0.5rem;
  box-shadow: 0 18px 50px rgba(0, 0, 0, 0.45);
  transform: translate(-50%, -50%);
  transform-origin: center center;
  /* Capa propia desde el inicio: la primera animacion no compite por el
     rasterizado con el resto de la pagina. */
  will-change: transform;
  cursor: zoom-out;
  user-select: none;
  -webkit-user-select: none;
  -webkit-user-drag: none;
}
.lightbox-img:focus { outline: none; }
.lightbox-img:focus-visible {
  outline: 2px solid rgba(255, 255, 255, 0.7);
  outline-offset: 4px;
}

/* Bloqueo de scroll sin coste: no se escribe scrollTop ni se usa
   position:fixed, asi que la pagina no se recoloca, no hay reflow del
   documento y la posicion del usuario se conserva exacta al cerrar. */
html.lb-lock { overflow: hidden; overscroll-behavior: none; }
html.lb-lock body { touch-action: none; }

/* === FADE IN ANIMATIONS === */
.fade-in {
  opacity: 0;
  transform: translateY(30px);
  transition: opacity 0.7s cubic-bezier(0.25, 0.46, 0.45, 0.94), transform 0.7s cubic-bezier(0.25, 0.46, 0.45, 0.94);
}
.fade-in.visible {
  opacity: 1;
  transform: translateY(0);
}
.fade-in-left {
  opacity: 0;
  transform: translateX(-30px);
  transition: opacity 0.7s ease-out, transform 0.7s ease-out;
}
.fade-in-left.visible {
  opacity: 1;
  transform: translateX(0);
}
.fade-in-right {
  opacity: 0;
  transform: translateX(30px);
  transition: opacity 0.7s ease-out, transform 0.7s ease-out;
}
.fade-in-right.visible {
  opacity: 1;
  transform: translateX(0);
}
.fade-in-scale {
  opacity: 0;
  transform: scale(0.95);
  transition: opacity 0.5s ease-out, transform 0.5s ease-out;
}
.fade-in-scale.visible {
  opacity: 1;
  transform: scale(1);
}

/* === CARD EFFECTS === */
.card {
  transition: all 0.3s cubic-bezier(0.25, 0.46, 0.45, 0.94);
}
.card:hover {
  transform: translateY(-4px);
  box-shadow: 0 8px 30px rgba(0, 0, 0, 0.12);
}
.card-glow:hover {
  box-shadow: 0 0 25px rgba(6, 182, 212, 0.08);
}

/* === MOUSE GLOW === */
.mouse-glow {
  position: fixed;
  width: 500px;
  height: 500px;
  pointer-events: none;
  background: radial-gradient(circle, rgba(6, 182, 212, 0.03) 0%, transparent 60%);
  transform: translate(-50%, -50%);
  z-index: 0;
  transition: left 0.08s linear, top 0.08s linear;
}

/* === NAVBAR SCROLL === */
.navbar {
  transition: background-color 0.3s ease, box-shadow 0.3s ease;
}

/* === SCROLL TO TOP === */
.scroll-top-btn {
  position: fixed;
  bottom: 2rem;
  right: 2rem;
  z-index: 50;
  opacity: 0;
  transform: translateY(20px);
  transition: opacity 0.3s ease, transform 0.3s ease;
  pointer-events: none;
}
.scroll-top-btn.visible {
  opacity: 1;
  transform: translateY(0);
  pointer-events: auto;
}

/* === BLOG === */
.post-content h2 { margin-top: 2rem; margin-bottom: 0.75rem; font-size: 1.5rem; font-weight: 700; }
.post-content h3 { margin-top: 1.5rem; margin-bottom: 0.5rem; font-size: 1.25rem; font-weight: 600; }
.post-content p { margin-bottom: 1rem; line-height: 1.75; }
.post-content ul, .post-content ol { margin-bottom: 1rem; padding-left: 1.5rem; }
.post-content li { margin-bottom: 0.25rem; }
.post-content code {
  background: var(--fallback-b3, oklch(var(--b3)));
  padding: 0.15rem 0.4rem;
  border-radius: 0.25rem;
  font-size: 0.875rem;
  font-family: ui-monospace, SFMono-Regular, monospace;
}
.post-content pre {
  background: var(--fallback-b3, oklch(var(--b3)));
  padding: 1rem;
  border-radius: 0.5rem;
  overflow-x: auto;
  margin-bottom: 1rem;
}
.post-content pre code {
  background: none;
  padding: 0;
  border-radius: 0;
}
.post-content blockquote {
  border-left: 3px solid var(--fallback-p, oklch(var(--p)));
  padding-left: 1rem;
  margin: 1rem 0;
  opacity: 0.85;
}
.post-content table {
  width: 100%;
  border-collapse: collapse;
  margin: 1rem 0;
}
.post-content th, .post-content td {
  border: 1px solid var(--fallback-b3, oklch(var(--b3)));
  padding: 0.5rem 0.75rem;
  text-align: left;
}
.post-content th {
  background: var(--fallback-b2, oklch(var(--b2)));
  font-weight: 600;
}
.post-content img {
  max-width: 100%;
  border-radius: 0.5rem;
  margin: 1rem 0;
}
.post-content a {
  color: var(--fallback-p, oklch(var(--p)));
  text-decoration: underline;
}

/* === NProgress-LIKE LOADING === */
#nprogress { pointer-events: none; }
#nprogress .bar {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 2px;
  background: var(--fallback-p, oklch(var(--p)));
  z-index: 9999;
  transform: scaleX(0);
  transform-origin: left;
  animation: nprogress 2s ease-out infinite;
}
@keyframes nprogress {
  0% { transform: scaleX(0); transform-origin: left; }
  50% { transform: scaleX(0.6); transform-origin: left; }
  100% { transform: scaleX(1); transform-origin: right; opacity: 0; }
}

/* === SMOOTH DROPDOWN === */
.dropdown-content {
  animation: dropdownIn 0.2s ease-out;
}
@keyframes dropdownIn {
  from { opacity: 0; transform: translateY(-8px); }
  to { opacity: 1; transform: translateY(0); }
}

/* === HISTORY: LIST + DETAIL (Experiencia y Comunidades) ===
   Patron unico para ambas secciones: lista resumida a la izquierda y un unico
   panel de detalle a la derecha. Solo el elemento seleccionado muestra su
   informacion completa, sin acumular contenido. */
.hist {
  display: grid;
  gap: 1rem;
  align-items: start;
}
@media (min-width: 1024px) {
  .hist { grid-template-columns: minmax(0, 20rem) minmax(0, 1fr); gap: 1.25rem; }
}

.hist-list {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}
@media (min-width: 1024px) {
  .hist-list {
    max-height: 32rem;
    overflow-y: auto;
    padding-right: 0.25rem;
    scrollbar-width: thin;
    scrollbar-color: var(--fallback-bc, oklch(var(--bc) / 0.2)) transparent;
  }
  .hist-list::-webkit-scrollbar { width: 4px; }
  .hist-list::-webkit-scrollbar-thumb {
    background: var(--fallback-bc, oklch(var(--bc) / 0.2));
    border-radius: 4px;
  }
}

.hist-item {
  display: block;
  width: 100%;
  text-align: left;
  padding: 0.7rem 0.875rem;
  border: 1px solid transparent;
  border-left: 3px solid transparent;
  border-radius: 0.625rem;
  background: var(--fallback-b1, oklch(var(--b1)));
  cursor: pointer;
  transition: background-color 0.22s ease, border-color 0.22s ease;
}
.hist-item:hover { border-color: var(--fallback-p, oklch(var(--p) / 0.25)); }
.hist-item[aria-selected="true"] {
  border-color: var(--fallback-p, oklch(var(--p) / 0.4));
  border-left-color: var(--fallback-p, oklch(var(--p)));
  background: var(--fallback-p, oklch(var(--p) / 0.07));
}
.hist-item:focus-visible {
  outline: 2px solid var(--fallback-p, oklch(var(--p)));
  outline-offset: 2px;
}

.hist-period {
  display: block;
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: 0.66rem;
  letter-spacing: 0.07em;
  text-transform: uppercase;
  opacity: 0.5;
}
.hist-company {
  display: block;
  font-weight: 600;
  font-size: 0.88rem;
  line-height: 1.3;
  margin-top: 0.15rem;
  overflow-wrap: break-word;
}
.hist-position {
  display: block;
  font-size: 0.77rem;
  line-height: 1.35;
  opacity: 0.65;
  margin-top: 0.1rem;
  overflow-wrap: break-word;
}
.hist-count {
  display: inline-block;
  margin-top: 0.3rem;
  font-size: 0.68rem;
  opacity: 0.5;
}

.hist-detail {
  background: var(--fallback-b2, oklch(var(--b2) / 0.5));
  border: 1px solid var(--fallback-b3, oklch(var(--bc) / 0.12));
  border-radius: 0.75rem;
  padding: 1.25rem;
  min-height: 12rem;
}
.hist-detail:focus-visible {
  outline: 2px solid var(--fallback-p, oklch(var(--p)));
  outline-offset: 2px;
}
.hist-detail:focus { outline: none; }

/* Cambio de contenido: entrada corta y discreta, sin saltos. */
@keyframes detailIn {
  from { opacity: 0; transform: translateY(6px); }
  to { opacity: 1; transform: none; }
}
.hist-detail.enter { animation: detailIn 260ms ease-out; }

/* Cabecera del panel de detalle */
.det-head { display: flex; align-items: flex-start; gap: 0.875rem; margin-bottom: 1rem; }
.det-icon {
  width: 2.5rem;
  height: 2.5rem;
  border-radius: 0.625rem;
  background: var(--fallback-p, oklch(var(--p) / 0.1));
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  overflow: hidden;
}
.det-icon img { width: 100%; height: 100%; object-fit: contain; }
.det-title { font-size: 1.1rem; font-weight: 700; line-height: 1.25; overflow-wrap: break-word; }
.det-role { color: var(--fallback-p, oklch(var(--p))); font-weight: 600; font-size: 0.88rem; margin-top: 0.15rem; overflow-wrap: break-word; }
.det-period {
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: 0.72rem;
  opacity: 0.55;
  margin-top: 0.3rem;
}

.det-lead {
  font-size: 0.85rem;
  line-height: 1.6;
  opacity: 0.8;
  margin-bottom: 0.875rem;
  overflow-wrap: break-word;
}

.det-group {
  border: 1px solid var(--fallback-bc, oklch(var(--bc) / 0.2));
  background: var(--fallback-b3, oklch(var(--b3) / 0.3));
  border-radius: 0.625rem;
  padding: 0.75rem 0.875rem;
  margin-bottom: 0.75rem;
}
.det-group:last-child { margin-bottom: 0; }
.det-group h5 {
  font-size: 0.68rem;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  opacity: 0.6;
  margin-bottom: 0.5rem;
  display: flex;
  align-items: center;
  gap: 0.375rem;
}
.det-group h5 svg { width: 0.875rem; height: 0.875rem; flex-shrink: 0; }
.det-group li {
  display: flex;
  align-items: flex-start;
  gap: 0.5rem;
  font-size: 0.82rem;
  opacity: 0.85;
  overflow-wrap: break-word;
}
.det-group li + li { margin-top: 0.35rem; }
.det-group li::before {
  content: '';
  width: 0.35rem;
  height: 0.35rem;
  border-radius: 50%;
  background: var(--fallback-p, oklch(var(--p)));
  flex-shrink: 0;
  margin-top: 0.5rem;
  opacity: 0.7;
}

.det-tags { display: flex; flex-wrap: wrap; gap: 0.375rem; margin-bottom: 0.875rem; }

/* Lista de actividades con marca de año */
.det-yeargroup {
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: 0.68rem;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  opacity: 0.5;
  margin: 0.875rem 0 0.5rem;
}
.det-yeargroup:first-child { margin-top: 0; }
.det-acts { position: relative; padding-left: 1.125rem; }
.det-acts::before {
  content: '';
  position: absolute;
  top: 0.4rem;
  bottom: 0.4rem;
  left: 0.25rem;
  width: 2px;
  background: var(--fallback-bc, oklch(var(--bc) / 0.12));
}
.det-act { position: relative; padding-bottom: 0.8rem; }
.det-act:last-child { padding-bottom: 0; }
.det-act::before {
  content: '';
  position: absolute;
  top: 0.35rem;
  left: -0.9375rem;
  width: 0.4rem;
  height: 0.4rem;
  border-radius: 50%;
  background: var(--fallback-p, oklch(var(--p) / 0.5));
}
.det-act-title { font-weight: 600; font-size: 0.82rem; line-height: 1.35; overflow-wrap: break-word; }
.det-act-desc {
  font-size: 0.79rem;
  line-height: 1.55;
  opacity: 0.7;
  margin-top: 0.15rem;
  overflow-wrap: break-word;
}

.hist-empty {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 10rem;
  opacity: 0.5;
  font-size: 0.85rem;
  text-align: center;
}

@media (max-width: 640px) {
  .hist-detail { padding: 1rem; }
  .det-title { font-size: 1rem; }
}

/* Respeta la preferencia del sistema: sin transiciones en el lightbox
   ni en el cambio de panel de detalle. El JS tambien lo comprueba. */
@media (prefers-reduced-motion: reduce) {
  .lightbox,
  .lightbox-img {
    transition: none !important;
  }
  .hist-detail.enter { animation: none; }
}
EOCSS

echo "  [OK] main.css generado"
echo ""

# =====================================================
# GENERATE app.js
# =====================================================

cat > "$OUTPUT/js/app.js" << 'APPJS'
(function () {
  'use strict';

  var S = typeof BLOGCV_SETTINGS !== 'undefined' ? BLOGCV_SETTINGS : {};
  var POSTS = typeof BLOGCV_POSTS !== 'undefined' ? BLOGCV_POSTS : [];
  var CURRENT_POST = typeof BLOGCV_CURRENT_POST !== 'undefined' ? BLOGCV_CURRENT_POST : null;
  var PER_PAGE = parseInt(S.posts_per_page) || 5;

  // ===== THEME =====
  var THEMES = { light: 'winter', dark: 'business' };
  var THEME_WEB = S.theme_web || 'dark';

  function setTheme(theme) {
    document.documentElement.setAttribute('data-theme', theme);
  }

  function initThemeToggle() {
    if (!document.getElementById('theme-toggle')) {
      var btn = document.createElement('button');
      btn.id = 'theme-toggle';
      btn.setAttribute('aria-label', 'Cambiar tema');
      btn.setAttribute('title', 'Cambiar tema');
      btn.innerHTML = '<i class="fa-solid fa-circle-half-stroke"></i>';
      document.body.appendChild(btn);
      btn.addEventListener('click', function () {
        var html = document.documentElement;
        var cur = html.getAttribute('data-theme');
        var next = cur === THEMES.dark ? THEMES.light : THEMES.dark;
        setTheme(next);
        localStorage.setItem('theme', next === THEMES.dark ? 'dark' : 'light');
      });
    }
    var saved = localStorage.getItem('theme');
    setTheme(saved ? (saved === 'dark' ? THEMES.dark : THEMES.light) : (THEME_WEB === 'dark' ? THEMES.dark : THEMES.light));
  }

  // ===== IMAGE LIGHTBOX =====
  // Un unico sistema de visualizacion. Se corregido sobre el anterior, sin
  // duplicarlo: el elemento <img> se crea una vez y se reutiliza siempre.
  //   clic/tap sobre la imagen -> abre
  //   clic/tap sobre la imagen -> cierra
  // ESC queda como atajo de accesibilidad (sin ningun control en pantalla).
  //
  // Rendimiento:
  //   - el tamano lo pone el CSS (max-width/max-height): cero layout por JS
  //   - solo se animan transform y opacity (GPU, sin reflow)
  //   - el bloqueo de scroll no escribe scrollTop ni usa position:fixed
  //   - la imagen se precarga al pasar el raton o al enfocarla
  //   - si se cierra a mitad de apertura, la animacion se invierte desde el
  //     fotograma actual (sin salto y sin reinicio)
  var lightbox = (function () {
    var OPEN_MS = 200;   // dentro del rango 150-250ms pedido
    var CLOSE_MS = 180;
    var EASE = 'cubic-bezier(0.2, 0.7, 0.3, 1)';
    // Escala de salida muy moderada: solo suaviza la entrada, nunca crece
    // hasta salirse de la pantalla.
    var SCALE_FROM = 0.96;
    var SHIFT = 0.35;    // porcion del viaje hacia la miniatura
    var REDUCED = !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
    var supportsWA = typeof Element !== 'undefined' && !!Element.prototype.animate;

    var root = null, stage = null, img = null;
    var state = 'closed';                 // closed | opening | open | closing
    var lastFocus = null, triggerRect = null;
    var rootAnim = null, imgAnim = null;
    var preloaded = {};

    function tf(tx, ty, s) {
      return 'translate(-50%, -50%) translate3d(' + tx + 'px,' + ty + 'px, 0) scale(' + s + ')';
    }

    // Punto de partida: cerca de la miniatura, nunca fuera de la pantalla.
    function fromThumb() {
      if (!triggerRect) return { tx: 0, ty: 0 };
      return {
        tx: (triggerRect.left + triggerRect.width / 2 - window.innerWidth / 2) * SHIFT,
        ty: (triggerRect.top + triggerRect.height / 2 - window.innerHeight / 2) * SHIFT
      };
    }

    function cancelAnims() {
      if (rootAnim) { rootAnim.cancel(); rootAnim = null; }
      if (imgAnim) { imgAnim.cancel(); imgAnim = null; }
    }

    // Espera real de la animacion: nunca un setTimeout que pueda desfasarse.
    function whenSettled() {
      var list = [rootAnim, imgAnim].filter(Boolean).map(function (a) {
        return a.finished.catch(function () {});
      });
      return Promise.all(list);
    }

    /* ---------- animaciones ---------- */
    function runOpen() {
      if (!supportsWA || REDUCED) {
        root.classList.add('open');
        state = 'open';
        return;
      }
      cancelAnims();

      var s = fromThumb();
      var opts = { duration: OPEN_MS, easing: EASE, fill: 'both' };
      rootAnim = root.animate([{ opacity: 0 }, { opacity: 1 }], opts);
      imgAnim = img.animate(
        [{ transform: tf(s.tx, s.ty, SCALE_FROM) }, { transform: tf(0, 0, 1) }],
        opts
      );
      // Se revela en el mismo frame en que ya estan aplicados el fondo y la
      // posicion inicial: nunca hay un instante con el marco negro vacio.
      root.classList.add('open');
      state = 'open';
      // Al terminar se liberan: el estado final es exactamente el del CSS.
      whenSettled().then(function () { if (state === 'open') cancelAnims(); });
    }

    function close() {
      if (state === 'closed' || state === 'closing') return;
      state = 'closing';

      // Si el overlay nunca llego a revelarse (por ejemplo, la imagen no se
      // pudo cargar), se retira de inmediato: animarlo produciria un destello.
      if (!root.classList.contains('open')) { finishClose(); return; }

      // Apertura todavia en curso: se invierte desde donde este. El cierre
      // empieza al instante, sin esperar a que la apertura acabe.
      if (supportsWA && imgAnim && imgAnim.playState === 'running' && rootAnim) {
        imgAnim.reverse();
        rootAnim.reverse();
        whenSettled().then(finishClose);
        return;
      }

      cancelAnims();
      if (REDUCED || !supportsWA) { finishClose(); return; }

      var s = fromThumb();
      var opts = { duration: CLOSE_MS, easing: EASE, fill: 'forwards' };
      imgAnim = img.animate(
        [{ transform: tf(0, 0, 1) }, { transform: tf(s.tx, s.ty, SCALE_FROM) }], opts
      );
      rootAnim = root.animate([{ opacity: 1 }, { opacity: 0 }], opts);
      whenSettled().then(finishClose);
    }

    function finishClose() {
      if (state !== 'closing') return;
      cancelAnims();
      root.classList.remove('open');
      unlockScroll();
      state = 'closed';
      if (lastFocus && lastFocus.focus) lastFocus.focus({ preventScroll: true });
      lastFocus = null;
    }

    /* ---------- scroll: no se mueve la pagina, no hay reflow ---------- */
    function lockScroll() {
      document.documentElement.classList.add('lb-lock');
    }

    function unlockScroll() {
      document.documentElement.classList.remove('lb-lock');
    }

    /* ---------- teclado ---------- */
    function onKeydown(e) {
      if (state === 'closed') return;
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(); return; }
      // El dialogo no contiene otros controles: el foco no puede salirse.
      if (e.key === 'Tab') { e.preventDefault(); img.focus(); }
    }

    /* ---------- construir una sola vez y reutilizar ---------- */
    function build() {
      if (root) return;
      root = document.createElement('div');
      root.className = 'lightbox';
      root.setAttribute('role', 'dialog');
      root.setAttribute('aria-modal', 'true');
      root.setAttribute('aria-label', 'Imagen ampliada');

      stage = document.createElement('div');
      stage.className = 'lightbox-stage';

      // Un unico <img> para todo: abrir y cerrar nunca crean otro elemento ni
      // vuelven a descargar una imagen ya cargada.
      img = document.createElement('img');
      img.className = 'lightbox-img';
      img.alt = '';
      img.draggable = false;
      img.tabIndex = -1;
      stage.appendChild(img);
      root.appendChild(stage);
      document.body.appendChild(root);

      root.addEventListener('click', function (e) {
        if (state === 'closed' || state === 'closing') return;
        if (e.target === img || e.target === stage || e.target === root) close();
      });
      document.addEventListener('keydown', onKeydown, true);
    }

    /* ---------- precarga: el clic ya no espera a la red ---------- */
    function preload(url) {
      if (!url || preloaded[url]) return;
      preloaded[url] = true;
      var probe = new Image();
      probe.src = url;
    }

    /* ---------- abrir ---------- */
    function show(trigger) {
      if (state !== 'closed') return;
      build();
      var url = trigger.getAttribute('data-full');
      if (!url) return;
      lastFocus = trigger;
      triggerRect = trigger.getBoundingClientRect();

      var alt = trigger.getAttribute('data-alt') || '';
      img.alt = alt;
      root.setAttribute('aria-label', alt ? 'Imagen ampliada: ' + alt : 'Imagen ampliada');

      state = 'opening';
      lockScroll();
      img.focus({ preventScroll: true });

      // Reutiliza la imagen si ya es la misma: no hay nueva peticion.
      if (img.getAttribute('src') === url && img.complete && img.naturalWidth > 0) {
        runOpen();
        return;
      }

      // Aun no esta decodificada. El overlay permanece oculto hasta que la
      // imagen este lista: runOpen revela fondo e imagen en el mismo frame,
      // de modo que nunca se ve un rectangulo negro vacio.
      img.style.opacity = '0';
      var onReady = function () {
        img.style.opacity = '';
        if (state !== 'opening') return;
        if (!img.naturalWidth) { close(); return; }
        runOpen();
      };
      if (img.decode) {
        img.src = url;
        img.decode().then(onReady, onReady);
      } else {
        img.onload = onReady;
        img.onerror = function () { img.style.opacity = ''; close(); };
        img.src = url;
      }
    }

    return {
      init: function () {
        document.addEventListener('click', function (e) {
          if (state !== 'closed') return;
          var trigger = e.target.closest && e.target.closest('.project-img-btn');
          if (trigger) { e.preventDefault(); show(trigger); }
        });
        // Precarga al apuntar o al enfocar: al hacer clic ya esta en cache.
        function warm(e) {
          var t = e.target.closest && e.target.closest('.project-img-btn');
          if (t) preload(t.getAttribute('data-full'));
        }
        document.addEventListener('mouseover', warm, { passive: true });
        document.addEventListener('focusin', warm, { passive: true });

        // Precarga en reposo de las primeras imagenes, sin datos moviles.
        var conn = navigator.connection;
        if (!conn || !conn.saveData) {
          var idle = window.requestIdleCallback || function (fn) { setTimeout(fn, 600); };
          idle(function () {
            var list = document.querySelectorAll('.project-img-btn[data-full]');
            for (var i = 0; i < list.length && i < 3; i++) {
              preload(list[i].getAttribute('data-full'));
            }
          });
        }
      }
    };
  })();

  // ===== UTILITIES =====
  function readingTime(text) {
    if (!text) return '1 min';
    var words = text.trim().split(/\s+/).length;
    return Math.max(1, Math.ceil(words / 200)) + ' min de lectura';
  }

  function slugify(text) {
    if (!text) return '';
    return text.toLowerCase().replace(/[^\w\sáéíóúñ]/g, '').replace(/\s+/g, '-').replace(/-+/g, '-').replace(/^-|-$/g, '');
  }

  function getImg(name) {
    if (!name) return '';
    return 'img/' + name.replace(/\.(png|jpg|jpeg|bmp|gif)$/i, '.webp');
  }

  // Escapa el contenido de los JSON antes de inyectarlo en el DOM.
  function escapeHtml(value) {
    if (value === null || value === undefined) return '';
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  var ICONS_MAP = {
    telegram: 'fa-brands fa-telegram', github: 'fa-brands fa-github',
    instagram: 'fa-brands fa-instagram', whatsapp: 'fa-brands fa-whatsapp',
    facebook: 'fa-brands fa-facebook', tiktok: 'fa-brands fa-tiktok',
    linkedin: 'fa-brands fa-linkedin', twitter: 'fa-brands fa-twitter',
    youtube: 'fa-brands fa-youtube', email: 'fa-solid fa-envelope',
    website: 'fa-solid fa-globe', link: 'fa-solid fa-link',
    'x-twitter': 'fa-brands fa-x-twitter', mastodon: 'fa-brands fa-mastodon',
    discord: 'fa-brands fa-discord', matrix: 'fa-solid fa-comment',
    peertube: 'fa-brands fa-peertube'
  };
  function iconClass(n) { return ICONS_MAP[n] || 'fa-solid fa-link'; }

  function renderMarkdown(text) {
    if (!text) return '';
    if (typeof marked !== 'undefined') {
      try { return marked.parse(text); } catch(e) {}
    }
    var h = text
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/^### (.+)$/gm, '<h3 class="text-lg font-bold mt-4 mb-2">$1</h3>')
      .replace(/^## (.+)$/gm, '<h2 class="text-xl font-bold mt-6 mb-2">$1</h2>')
      .replace(/^# (.+)$/gm, '<h1 class="text-2xl font-bold mt-6 mb-3">$1</h1>')
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\*(.+?)\*/g, '<em>$1</em>')
      .replace(/`([^`]+)`/g, '<code class="bg-base-300 px-1.5 py-0.5 rounded text-sm">$1</code>')
      .replace(/^- (.+)$/gm, '<li class="ml-4 list-disc">$1</li>')
      .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" class="link link-primary" target="_blank" rel="noopener">$1</a>')
      .replace(/\n\n/g, '</p><p class="mb-2">')
      .replace(/\n/g, '<br>');
    return '<p class="mb-2">' + h + '</p>';
  }

  function getSummary(content, maxLen) {
    if (!content) return '';
    maxLen = maxLen || 200;
    var clean = content.replace(/^---[\s\S]*?---/, '').replace(/^# .+\n?/, '').replace(/[#*`>\[\]]/g, '').trim();
    if (clean.length <= maxLen) return clean;
    return clean.substring(0, maxLen).replace(/\s+\S*$/, '') + '...';
  }

  function getPostBySlug(slug) {
    for (var i = 0; i < POSTS.length; i++) {
      if (POSTS[i].slug === slug || slugify(POSTS[i].title) === slug) return POSTS[i];
    }
    return null;
  }

  // ===== SCHEMA =====
  function injectSchema() {
    if (document.querySelector('script[type="application/ld+json"]')) return;
    var S2 = typeof BLOGCV_SETTINGS !== 'undefined' ? BLOGCV_SETTINGS : {};
    var CONTACTS = typeof BLOGCV_CONTACTS !== 'undefined' ? BLOGCV_CONTACTS : {};
    var social = [];
    if (CONTACTS.social) {
      CONTACTS.social.forEach(function (s) { if (s.enabled !== false && s.url) social.push(s.url); });
    }
    var url = S2.site_url || 'https://' + (S2.username || '') + '.github.io/';
    var script = document.createElement('script');
    script.type = 'application/ld+json';
    script.textContent = JSON.stringify({
      '@context': 'https://schema.org', '@type': 'Person',
      name: S2.fullname || '', alternateName: S2.username || '',
      jobTitle: S2.professional_title || '', description: S2.site_description || '',
      url: url.replace(/\/+$/, '') + '/', sameAs: social
    });
    document.head.appendChild(script);
  }

  // ===== SCROLL & NAV =====
  function initScroll() {
    document.addEventListener('click', function (e) {
      var a = e.target.closest('a[href^="#"]');
      if (!a) return;
      var href = a.getAttribute('href');
      if (href && href.startsWith('#!')) return;
      e.preventDefault();
      var id = href ? href.slice(1) : '';
      var t = document.getElementById(id);
      if (t) {
        var y = t.getBoundingClientRect().top + window.scrollY - 80;
        window.scrollTo({ top: y, behavior: 'smooth' });
      }
    });

    if (window.location.hash && !window.location.hash.startsWith('#!')) {
      setTimeout(function () {
        var id = window.location.hash.slice(1);
        var t = document.getElementById(id);
        if (t) {
          var y = t.getBoundingClientRect().top + window.scrollY - 80;
          window.scrollTo({ top: y, behavior: 'smooth' });
        }
      }, 300);
    }
  }

  function initScrollToTop() {
    var btn = document.createElement('button');
    btn.className = 'scroll-top-btn btn btn-circle btn-primary shadow-lg';
    btn.innerHTML = '<i class="fa-solid fa-arrow-up" aria-hidden="true"></i>';
    btn.setAttribute('aria-label', 'Volver arriba');
    document.body.appendChild(btn);
    btn.addEventListener('click', function () { window.scrollTo({ top: 0, behavior: 'smooth' }); });
    // rAF para no disparar trabajo de layout en cada evento de scroll.
    var visible = false;
    var ticking = false;
    window.addEventListener('scroll', function () {
      if (ticking) return;
      ticking = true;
      window.requestAnimationFrame(function () {
        var show = window.scrollY > 400;
        if (show !== visible) {
          visible = show;
          btn.classList.toggle('visible', show);
        }
        ticking = false;
      });
    }, { passive: true });

    /* Flechas del teclado: scroll suave con el mismo scrollTo que usa el resto
       del sitio. No sustituye al comportamiento nativo mas de lo necesario:
       si el foco esta en un campo editable o en un control que ya capturo la
       flecha, no hace nada. Un unico listener, registrado una sola vez porque
       esta funcion se invoca una vez en cada rama de arranque. */
    var kbTarget = null;   // destino acumulado mientras se mantiene pulsada
    var kbReset = null;
    function clearTimer() { if (kbReset) { clearTimeout(kbReset); kbReset = null; } }
    // Descarta el destino acumulado: el usuario ha tomado el control.
    function forget() { kbTarget = null; clearTimer(); }
    // Igual que forget pero sin tocar el temporizador que la programme.
    function dropTarget() { kbTarget = null; }
    function initKeyboardScroll() {
      // Si el usuario toma el control con rueda o tactil, se descarta el
      // destino acumulado para no pelearnos con el scroll nativo.
      window.addEventListener('wheel', forget, { passive: true });
      window.addEventListener('touchstart', forget, { passive: true });

      document.addEventListener('keydown', function (e) {
        // Otro control (p. ej. la lista role="tablist") ya resolvio la flecha.
        if (e.defaultPrevented) return;
        if (e.altKey || e.ctrlKey || e.metaKey) return;   // atajos del navegador

        var dir = e.key === 'ArrowDown' ? 1 : e.key === 'ArrowUp' ? -1 : 0;
        if (!dir) return;

        var el = e.target && e.target.nodeType === 1 ? e.target : e.target && e.target.parentElement;
        if (el && el.closest('input, textarea, select, [contenteditable=""], [contenteditable="true"], [role="tablist"]')) return;
        // Con el visor de imagenes abierto la pagina esta bloqueada.
        if (document.documentElement.classList.contains('lb-lock')) return;

        // Paso comodo: una fraccion de la pantalla, acotada para que no sea ni
        // un salto brusco ni un avance imperceptible.
        var step = Math.min(320, Math.max(90, Math.round(window.innerHeight * 0.12)));
        var max = document.documentElement.scrollHeight - window.innerHeight;
        var base = kbTarget === null ? window.scrollY : kbTarget;
        kbTarget = Math.max(0, Math.min(max, base + dir * step));

        e.preventDefault();
        window.scrollTo({ top: kbTarget, behavior: 'smooth' });

        clearTimer();
        kbReset = setTimeout(dropTarget, 140);
      });

      // Al soltar la tecla se reinicia el destino: la siguiente pulsacion
      // parte de donde esta la pagina de verdad.
      document.addEventListener('keyup', function (e) {
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') forget();
      });
    }
    initKeyboardScroll();
  }

  // ===== EFFECTS =====
  function initFadeIn() {
    var els = document.querySelectorAll('.fade-in, .fade-in-left, .fade-in-right, .fade-in-scale');
    if (!els.length) return;
    var obs = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
          obs.unobserve(entry.target);
        }
      });
    }, { threshold: 0.1, rootMargin: '0px 0px -50px 0px' });
    els.forEach(function (el) { obs.observe(el); });
  }

  function initMouseGlow() {
    if (S.mouse_glow === false) return;
    var glow = document.createElement('div');
    glow.className = 'mouse-glow';
    document.body.appendChild(glow);
    document.addEventListener('mousemove', function (e) {
      glow.style.left = e.clientX + 'px';
      glow.style.top = e.clientY + 'px';
    });
  }

  // ===== MAIN PAGE CACHE =====
  var MAIN_HTML = null;

  // ===== BLOG STATE =====
  var blogState = { page: 0, perPage: PER_PAGE, query: '' };
  var blogSearchBound = false;
  var panelsBound = false;

  function filteredPosts() {
    var q = blogState.query.toLowerCase().trim();
    if (!q) return POSTS;
    return POSTS.filter(function (p) {
      var txt = (p.title || '') + ' ' + (p.category || '') + ' ' + (p.tags || '') + ' ' + (p.content || '');
      return txt.toLowerCase().includes(q);
    });
  }

  function renderBlogPosts() {
    var all = filteredPosts();
    var end = blogState.perPage * (blogState.page + 1);
    var shown = blogState.query ? all : all.slice(0, end);

    if (!shown.length) {
      return '<p class="text-center opacity-70 py-8">No se encontraron artículos.</p>';
    }

    var html = shown.map(function (post) {
      var summary = getSummary(post.content, 180);
      return '<div class="card bg-base-100 shadow-xl hover:shadow-2xl transition-all duration-300 fade-in blog-card">' +
        '<div class="card-body">' +
        '<div class="flex flex-wrap gap-2 items-center mb-1">' +
        (post.category ? '<span class="badge badge-primary badge-sm">' + post.category + '</span>' : '') +
        (post.date ? '<span class="text-xs opacity-70 font-mono">' + post.date + '</span>' : '') +
        '</div>' +
        '<h3 class="card-title text-lg">' + (post.title || '') + '</h3>' +
        (post.tags ? '<div class="flex flex-wrap gap-1">' + post.tags.split(',').map(function (t) { return '<span class="badge badge-ghost badge-xs">' + t.trim() + '</span>'; }).join('') + '</div>' : '') +
        '<p class="text-sm mt-2 opacity-80">' + summary + '</p>' +
        '<div class="card-actions justify-between items-center mt-4">' +
        '<span class="text-xs opacity-60">' + readingTime(post.content) + '</span>' +
        '<a href="#!post/' + (post.slug || slugify(post.title)) + '" class="btn btn-primary btn-sm">Leer más</a>' +
        '</div></div></div>';
    }).join('\n');

    if (!blogState.query && end < all.length) {
      html += '<div class="text-center mt-10">' +
        '<button class="btn btn-outline load-more-btn" data-remaining="' + (all.length - end) + '">' +
        'Cargar más artículos (' + (all.length - end) + ' restantes)' +
        '</button></div>';
    }
    return html;
  }

  function updateBlogPosts() {
    var container = document.getElementById('blog-posts');
    if (!container) return;
    container.innerHTML = renderBlogPosts();
    initFadeIn();
  }

  function initBlogSearch() {
    if (blogSearchBound) return;
    blogSearchBound = true;
    document.addEventListener('input', function (e) {
      if (e.target.id === 'blog-search') {
        blogState.query = e.target.value;
        blogState.page = 0;
        updateBlogPosts();
      }
    });
    document.addEventListener('click', function (e) {
      var btn = e.target.closest('.load-more-btn');
      if (btn) {
        blogState.page++;
        updateBlogPosts();
      }
      var copyBtn = e.target.closest('.copy-link-btn');
      if (copyBtn) {
        navigator.clipboard.writeText(window.location.href).catch(function () {});
      }
    });
  }

  // ===== POST VIEW =====
  function showPost(slug) {
    var post = getPostBySlug(slug);
    if (!post) { restoreMainPage(); return; }
    var app = document.getElementById('app');
    if (!app) return;
    if (MAIN_HTML === null) MAIN_HTML = app.innerHTML;

    var CONTACTS = typeof BLOGCV_CONTACTS !== 'undefined' ? BLOGCV_CONTACTS : {};
    var S2 = typeof BLOGCV_SETTINGS !== 'undefined' ? BLOGCV_SETTINGS : {};

    function fmtDate(start, end) {
      if (!end || end === start) return start || '';
      return (start || '') + ' — ' + (end || '');
    }

    var html = renderMarkdown(post.content || '');
    var raw = post.content || '';

    var headings = raw.match(/^#{2,3}\s.+$/gm) || [];
    var tocHtml = '';
    if (headings.length > 1) {
      tocHtml = headings.map(function (h) {
        var lvl = (h.match(/^#+/g) || [''])[0].length;
        var text = h.replace(/^#+\s*/, '');
        var id = slugify(text);
        return '<li class="' + (lvl === 3 ? 'ml-4' : '') + '"><a href="#' + id + '" class="link link-hover text-sm">' + text + '</a></li>';
      }).join('\n');
    }

    var shareUrl = encodeURIComponent(window.location.href);
    var shareText = encodeURIComponent(post.title || '');

    app.innerHTML =
      '<nav class="navbar bg-base-100/90 backdrop-blur-md shadow-sm sticky top-0 z-50">' +
      '<div class="navbar-start"><a class="btn btn-ghost text-lg md:text-xl" href="#hero">' + (S2.site_title || '') + '</a></div>' +
      '<div class="navbar-end">' +
      '<a class="btn btn-primary" href="#contact">Contactar</a></div></nav>' +
      '<main class="min-h-screen bg-base-200 py-8">' +
      '<article class="max-w-3xl mx-auto px-4">' +
      '<a href="#" class="link link-hover text-sm opacity-70 hover:opacity-100 inline-flex items-center gap-1 mb-4" onclick="window.history.back();return false;">' +
      '<i class="fa-solid fa-arrow-left"></i> Volver</a>' +
      '<h1 class="text-3xl md:text-4xl font-bold mt-2 fade-in">' + (post.title || '') + '</h1>' +
      '<div class="flex flex-wrap gap-4 mt-4 text-sm opacity-70 fade-in">' +
      (post.date ? '<span><i class="fa-regular fa-calendar mr-1"></i>' + post.date + '</span>' : '') +
      '<span><i class="fa-regular fa-clock mr-1"></i>' + readingTime(post.content) + '</span>' +
      (post.category ? '<span class="badge badge-primary badge-sm">' + post.category + '</span>' : '') +
      '</div>' +
      (post.tags ? '<div class="flex flex-wrap gap-1 mt-3 fade-in">' +
        post.tags.split(',').map(function (t) { return '<span class="badge badge-ghost badge-sm">' + t.trim() + '</span>'; }).join('') +
        '</div>' : '') +
      (tocHtml ? '<div class="card bg-base-300/50 p-5 mt-8 fade-in"><h4 class="font-bold mb-3 text-sm uppercase tracking-wider opacity-70">Contenido</h4><ul class="space-y-1.5">' + tocHtml + '</ul></div>' : '') +
      '<div class="post-content mt-10 fade-in">' + html + '</div>' +
      '<div class="divider mt-16"></div>' +
      '<div class="flex flex-wrap items-center gap-3 mb-8 fade-in">' +
      '<span class="text-sm font-semibold">Compartir:</span>' +
      '<a href="https://twitter.com/intent/tweet?text=' + shareText + '&url=' + shareUrl + '" target="_blank" rel="noopener" class="btn btn-ghost btn-sm btn-circle" aria-label="Compartir en X"><i class="fa-brands fa-x-twitter"></i></a>' +
      '<a href="https://www.linkedin.com/sharing/share-offsite/?url=' + shareUrl + '" target="_blank" rel="noopener" class="btn btn-ghost btn-sm btn-circle" aria-label="Compartir en LinkedIn"><i class="fa-brands fa-linkedin"></i></a>' +
      '<a href="https://wa.me/?text=' + shareText + '%20' + shareUrl + '" target="_blank" rel="noopener" class="btn btn-ghost btn-sm btn-circle" aria-label="Compartir en WhatsApp"><i class="fa-brands fa-whatsapp"></i></a>' +
      '<button class="btn btn-ghost btn-sm btn-circle copy-link-btn" aria-label="Copiar enlace"><i class="fa-solid fa-link"></i></button>' +
      '</div>' +
      '<div class="text-center mb-12 fade-in">' +
      '<a href="#" class="btn btn-outline btn-sm" onclick="window.history.back();return false;"><i class="fa-solid fa-arrow-left mr-1"></i> Ver más artículos</a>' +
      ' <a href="#contact" class="btn btn-primary btn-sm"><i class="fa-solid fa-envelope mr-1"></i> Contactar</a>' +
      '</div></article></main>' +
      '<footer class="footer footer-center p-6 bg-base-300 text-base-content"><aside><p class="text-sm">&copy; ' + new Date().getFullYear() + ' ' + (S2.fullname || '') + '. ' + (S2.copyright || '') + '</p></aside></footer>';

    window.location.hash = '!post/' + (post.slug || slugify(post.title));
    window.scrollTo({ top: 0 });
    initFadeIn();
  }

  // Los paneles de Comunidades/Experiencia se renderizan en tiempo de ejecución.
  // MAIN_HTML se capturó antes de ese render, así que tras restaurar el DOM
  // hay que repoblarlos o quedarían vacíos.
  function initInteractivePanels() {
    var comRoot = document.getElementById('communities-list');
    if (comRoot && !comRoot.children.length) initCommunities();
    var jobRoot = document.getElementById('jobs-list');
    if (jobRoot && !jobRoot.children.length) initJobs();
  }

  function restoreMainPage() {
    var app = document.getElementById('app');
    if (!app || MAIN_HTML === null) {
      window.location.reload();
      return;
    }
    app.innerHTML = MAIN_HTML;
    initFadeIn();
    initBlogSearch();
    initInteractivePanels();
    var curTheme = document.documentElement.getAttribute('data-theme');
    if (curTheme) setTheme(curTheme);
    if (window.location.hash) {
      setTimeout(function () {
        var id = window.location.hash.slice(1);
        var t = document.getElementById(id);
        if (t) {
          var y = t.getBoundingClientRect().top + window.scrollY - 80;
          window.scrollTo({ top: y, behavior: 'smooth' });
        }
      }, 100);
    }
  }

  // ===== SHARED ACCORDION BEHAVIOUR =====
  // Un unico patron para Comunidades y Experiencia: la cabecera siempre
  // visible muestra la informacion principal y el cuerpo se despliega con la
  // informacion secundaria. teclado: Enter/Espacio alterna, flechas recorren.
  /* ------------------------------------------------------------------
     LISTA + PANEL DE DETALLE (compartido por Experiencia y Comunidades)
     Solo un elemento puede estar seleccionado a la vez. La lista usa
     semantica de tabs: el paneldepende de la pestana seleccionada.
     ------------------------------------------------------------------ */
  function initHistoryList(listEl, detailEl, items, render) {
    if (!listEl || !detailEl) return;
    var current = 0;
    var tabs = [];
    // Los id se prefijan por seccion: 'hist-tab-0' se repetiria en las dos
    // listas y aria-controls / aria-labelledby apuntarian al elemento equivocado.
    var prefix = (detailEl.id || 'hist') + '-tab-';

    function paint() {
      for (var i = 0; i < items.length; i++) {
        var t = tabs[i];
        if (!t) continue;
        var on = i === current;
        t.setAttribute('aria-selected', on ? 'true' : 'false');
        t.tabIndex = on ? 0 : -1;
      }
      detailEl.setAttribute('aria-labelledby', prefix + current);
      detailEl.innerHTML = render(items[current], current);
      // Re-dispara la entrada corta del panel en cada cambio.
      detailEl.classList.remove('enter');
      void detailEl.offsetWidth;
      detailEl.classList.add('enter');
    }

    function select(i, focus) {
      if (!items.length) return;
      current = Math.max(0, Math.min(items.length - 1, i));
      paint();
      if (focus && tabs[current]) tabs[current].focus();
    }

    listEl.innerHTML = items.map(function (it, i) {
      return '<button type="button" class="hist-item" role="tab" id="' + prefix + i + '"' +
        ' aria-controls="' + detailEl.id + '" aria-selected="false" tabindex="-1"' +
        ' data-index="' + i + '">' + it.rowHTML + '</button>';
    }).join('');
    tabs = Array.prototype.slice.call(listEl.querySelectorAll('.hist-item'));

    listEl.addEventListener('click', function (e) {
      var t = e.target.closest('.hist-item');
      if (t) select(parseInt(t.getAttribute('data-index'), 10) || 0, false);
    });

    // Navegacion con teclado sobre la lista.
    listEl.addEventListener('keydown', function (e) {
      var k = e.key;
      var i = current;
      if (k === 'ArrowDown' || k === 'ArrowRight') { select(i + 1, true); }
      else if (k === 'ArrowUp' || k === 'ArrowLeft') { select(i - 1, true); }
      else if (k === 'Home') { select(0, true); }
      else if (k === 'End') { select(items.length - 1, true); }
      else return;
      e.preventDefault();
    });

    // Primera entrada seleccionada para no mostrar un panel vacio.
    select(0, false);
  }

  function groupList(title, icon, items) {
    if (!items || !items.length) return '';
    return '<div class="det-group"><h5>' + icon + title + '</h5><ul>' +
      items.map(function (x) { return '<li><span>' + escapeHtml(x) + '</span></li>'; }).join('') +
      '</ul></div>';
  }

  function tagList(tech) {
    if (!tech || !tech.length) return '';
    return '<div class="det-tags">' + tech.map(function (t) {
      return '<span class="badge badge-sm badge-outline">' + escapeHtml(t) + '</span>';
    }).join('') + '</div>';
  }

  function initCommunities() {
    var listEl = document.getElementById('communities-list');
    var detailEl = document.getElementById('communities-detail');
    var root = document.getElementById('communities-container');
    if (!root) return;

    var enabled = BLOGCV_COMMUNITIES.filter(function (c) { return c.enabled; });
    enabled.sort(function (a, b) { return (b.from || '').localeCompare(a.from || ''); });
    if (!enabled.length) {
      listEl.innerHTML = '';
      detailEl.innerHTML = '<div class="hist-empty">No hay comunidades registradas.</div>';
      return;
    }

    function communityLogo(c) {
      if (c.logo) return '<img src="' + escapeHtml(getImg(c.logo)) + '" alt="" loading="lazy">';
      // Sin archivo de logo: icono generico para no dejar el hueco vacio.
      return '<svg class="w-5 h-5" style="color: var(--fallback-p, oklch(var(--p)));" fill="none" viewBox="0 0 24 24" stroke="currentColor">' +
        '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"/></svg>';
    }

    var items = enabled.map(function (c) {
      var count = (c.activities || []).length;
      var period = (c.from || '') + (c.to ? ' - ' + escapeHtml(c.to) : ' - Actualidad');
      return {
        data: c,
        rowHTML:
          '<span class="hist-period">' + period + '</span>' +
          '<span class="hist-company">' + escapeHtml(c.name) + '</span>' +
          (c.role ? '<span class="hist-position">' + escapeHtml(c.role) + '</span>' : '') +
          '<span class="hist-count">' + count + ' ' + (count === 1 ? 'actividad' : 'actividades') + '</span>'
      };
    });

    initHistoryList(listEl, detailEl, items, function (item) {
      var c = item.data;
      // Actividades agrupadas por ano: orden legible y compacto.
      var byYear = {};
      (c.activities || []).forEach(function (a) {
        var y = a.year ? String(a.year) : '';
        if (!byYear[y]) byYear[y] = [];
        byYear[y].push(a);
      });
      var years = Object.keys(byYear).sort(function (a, b) { return b.localeCompare(a); });

      return '<div class="det-head">' +
          '<div class="det-icon">' + communityLogo(c) + '</div>' +
          '<div><h3 class="det-title">' + escapeHtml(c.name) + '</h3>' +
          (c.role ? '<div class="det-role">' + escapeHtml(c.role) + '</div>' : '') +
          '<div class="det-period">' + escapeHtml(c.from || '') + (c.to ? ' - ' + escapeHtml(c.to) : ' - Actualidad') +
          ' &middot; ' + (c.activities || []).length + ' actividades</div></div>' +
        '</div>' +
        (c.description ? '<p class="det-lead">' + escapeHtml(c.description) + '</p>' : '') +
        years.map(function (y) {
          return '<div class="det-yeargroup">' + escapeHtml(y) + '</div>' +
            '<div class="det-acts">' + byYear[y].map(function (a) {
              return '<div class="det-act"><div class="det-act-title">' + escapeHtml(a.title) + '</div>' +
                (a.description ? '<div class="det-act-desc">' + escapeHtml(a.description) + '</div>' : '') +
                '</div>';
            }).join('') + '</div>';
        }).join('');
    });
  }

  function initJobs() {
    var listEl = document.getElementById('jobs-list');
    var detailEl = document.getElementById('jobs-detail');
    var root = document.getElementById('jobs-container');
    if (!root) return;

    var enabled = BLOGCV_JOBS.filter(function (j) { return j.enabled; });
    enabled.sort(function (a, b) { return (b.from || '').localeCompare(a.from || ''); });
    if (!enabled.length) {
      listEl.innerHTML = '';
      detailEl.innerHTML = '<div class="hist-empty">No hay experiencia registrada.</div>';
      return;
    }

    var items = enabled.map(function (j) {
      return {
        data: j,
        rowHTML:
          '<span class="hist-period">' + escapeHtml(j.from || '') + (j.to ? ' - ' + escapeHtml(j.to) : ' - Actualidad') + '</span>' +
          '<span class="hist-company">' + escapeHtml(j.company) + '</span>' +
          (j.position ? '<span class="hist-position">' + escapeHtml(j.position) + '</span>' : '')
      };
    });

    initHistoryList(listEl, detailEl, items, function (item) {
      var j = item.data;
      var out = '<div class="det-head"><div class="det-icon"><i class="fa-solid fa-briefcase text-lg"></i></div><div>' +
        '<h3 class="det-title">' + escapeHtml(j.company) + '</h3>' +
        (j.position ? '<div class="det-role">' + escapeHtml(j.position) + '</div>' : '') +
        '<div class="det-period">' + escapeHtml(j.from || '') + (j.to ? ' - ' + escapeHtml(j.to) : ' - Actualidad') + '</div>' +
        '</div></div>';

      if (j.summary) out += '<p class="det-lead">' + escapeHtml(j.summary) + '</p>';
      out += tagList(j.technologies);
      out += groupList('Responsabilidades', '<i class="fa-solid fa-list-check"></i>', j.responsibilities);
      out += groupList('Implementaciones', '<i class="fa-solid fa-code"></i>', j.implementations);
      out += groupList('Logros', '<i class="fa-solid fa-star"></i>', j.achievements);

      if (j.gallery && j.gallery.length) {
        out += '<div class="det-group"><h5><i class="fa-solid fa-images"></i>Galería</h5>' +
          '<div class="grid grid-cols-2 gap-2 sm:grid-cols-3">' + j.gallery.map(function (g) {
            return '<img src="' + escapeHtml(g.src || g) + '" alt="' + escapeHtml(g.alt || '') + '" loading="lazy" class="rounded-lg w-full h-24 object-cover">';
          }).join('') + '</div></div>';
      }
      return out;
    });
  }

  function initRouting() {
    var hash = window.location.hash;
    if (hash.startsWith('#!post/')) {
      var slug = hash.replace('#!post/', '');
      var post = getPostBySlug(slug);
      if (post) {
        setTimeout(function () { showPost(slug); }, 50);
        return;
      }
    }
  }

  window.addEventListener('hashchange', function () {
    var hash = window.location.hash;
    if (hash.startsWith('#!post/')) {
      showPost(hash.replace('#!post/', ''));
    } else {
      if (MAIN_HTML !== null) {
        restoreMainPage();
      }
    }
  });

  // ===== INIT =====
  document.addEventListener('DOMContentLoaded', function () {
    if (CURRENT_POST) {
      injectSchema();
      initThemeToggle();
      initScrollToTop();
      initMouseGlow();
      initFadeIn();
      lightbox.init();
      return;
    }
    MAIN_HTML = document.getElementById('app') ? document.getElementById('app').innerHTML : null;
    injectSchema();
    initThemeToggle();
    initScroll();
    initScrollToTop();
    initMouseGlow();
    initFadeIn();
    initBlogSearch();
    initCommunities();
    initJobs();
    initRouting();
    lightbox.init();
  });
})();
APPJS

echo "  [OK] app.js generado"
echo ""

# =====================================================
# GENERATE POST PAGES
# =====================================================

mkdir -p "$OUTPUT/post"
POST_COUNT=0

for post in assets/posts/*.md; do
  [ -f "$post" ] || continue
  filename=$(basename "$post" .md)
  slug="$filename"

  title=""; date=""; category=""; tags=""; image=""
  content=""
  if head -1 "$post" | grep -q '^---$'; then
    title=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="title"{sub(/^[^:]*: /,"");print}' "$post")
    date=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="date"{sub(/^[^:]*: /,"");print}' "$post")
    category=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="category"{sub(/^[^:]*: /,"");print}' "$post")
    tags=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="tags"{sub(/^[^:]*: /,"");print}' "$post")
    image=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="image"{sub(/^[^:]*: /,"");print}' "$post")
    content=$(awk 'BEGIN{c=0} /^---$/{c++;next} c>=2{print}' "$post")
  fi
  [ -z "$title" ] && title=$(grep '^# ' "$post" | head -1 | sed 's/^# //')
  [ -z "$date" ] && echo "$filename" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' && date=$(echo "$filename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')

  e_title=$(echo "$title" | html_esc)
  e_cat=$(echo "$category" | html_esc)
  e_tags=$(echo "$tags" | html_esc)

  # Convert markdown content to HTML for pre-rendering
  post_body_html=""
  if command -v marked &>/dev/null; then
    post_body_html=$(echo "$content" | marked 2>/dev/null)
  elif command -v python3 &>/dev/null; then
    post_body_html=$(python3 -c "import sys,markdown; print(markdown.markdown(sys.stdin.read()))" 2>/dev/null <<< "$content" || echo "<pre>${content}</pre>")
  else
    post_body_html=$(echo "$content" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/^## \(.*\)/<h2>\1<\/h2>/g; s/^# \(.*\)/<h1>\1<\/h1>/g' | sed 's/^ - \(.*\)/<li>\1<\/li>/g' | sed 's/\*\*\([^*]*\)\*\*/<b>\1<\/b>/g' | sed 's/\*\([^*]*\)\*/<i>\1<\/i>/g')
  fi
  [ -z "$post_body_html" ] && post_body_html=$(echo "$content" | html_esc | sed 's/$/<br>/g')

  # Build content sections
  tags_html=""
  [ -n "$tags" ] && tags_html=$(echo "$tags" | sed 's/, */<\/span><span class="badge badge-ghost badge-sm">/g; s/^/<span class="badge badge-ghost badge-sm">/; s/$/<\/span>/')

  # Compute reading time
  wc=$(echo "$content" | wc -w)
  rt="1 min de lectura"
  [ "$wc" -gt 0 ] && rt="$(( (wc + 199) / 200 )) min de lectura"

  # Build TOC from headings
  toc_html=""
  headings=$(echo "$content" | grep -E '^#{2,3} ')
  hcount=$(echo "$headings" | grep -c '')
  if [ "$hcount" -gt 1 ] 2>/dev/null; then
    toc_html=$(echo "$headings" | while read -r line; do
      level=$(echo "$line" | grep -o '^#\+' | wc -c)
      text=$(echo "$line" | sed 's/^#* //')
      id=$(echo "$text" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9áéíóúñ ]//g; s/ /-/g')
      if [ "$level" -eq 4 ]; then
        echo "<li class=\"ml-4\"><a href=\"#${id}\" class=\"link link-hover text-sm\">${text}</a></li>"
      else
        echo "<li><a href=\"#${id}\" class=\"link link-hover text-sm\">${text}</a></li>"
      fi
    done | tr -d '\n')
    toc_html="<div class=\"card bg-base-300/50 p-5 mt-8 fade-in\"><h4 class=\"font-bold mb-3 text-sm uppercase tracking-wider opacity-70\">Contenido</h4><ul class=\"space-y-1.5\">${toc_html}</ul></div>"
  fi

  cat > "$OUTPUT/post/${slug}.html" << POSTPAGE
<!DOCTYPE html>
<html lang="${LANG}" data-theme="${THEME}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${e_title} | ${SITE_TITLE}</title>
  <meta name="description" content="${SITE_DESC}">
  <meta property="og:title" content="${e_title} | ${SITE_TITLE}">
  <meta property="og:description" content="${SITE_DESC}">
  <meta property="og:url" content="${SITE_URL}post/${slug}.html">
  <meta property="og:type" content="article">
  <meta name="keywords" content="${SEO_KW}">
  <link rel="canonical" href="${SITE_URL}post/${slug}.html">
  <link rel="icon" type="image/webp" href="../img/${FAVICON_WEBP}">
  <script src="https://cdn.tailwindcss.com"></script>
  <link href="https://cdn.jsdelivr.net/npm/daisyui@4.12.14/dist/full.min.css" rel="stylesheet" type="text/css" />
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.6.0/css/all.min.css">
  <link rel="stylesheet" href="../css/main.css">
  <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
  <script>
const BLOGCV_SETTINGS = $(cat assets/settings.json);
const BLOGCV_PROFILE = $(cat assets/profile.json);
const BLOGCV_PROJECTS = $(cat assets/projects.json);
const BLOGCV_JOBS = $(cat assets/jobs.json);
const BLOGCV_COMMUNITIES = $(cat assets/communities.json);
const BLOGCV_CONTACTS = $(cat assets/contacts.json);
const BLOGCV_POSTS = [
POSTPAGE

  # Embed all posts data
  FIRST=true
  for spost in assets/posts/*.md; do
    [ -f "$spost" ] || continue
    $FIRST || echo "," >> "$OUTPUT/post/${slug}.html"
    FIRST=false
    sfilename=$(basename "$spost" .md)
    sslug="$sfilename"
    stitle=""; sdate=""; scat=""; stags=""; simage=""
    if head -1 "$spost" | grep -q '^---$'; then
      stitle=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="title"{sub(/^[^:]*: /,"");print}' "$spost")
      sdate=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="date"{sub(/^[^:]*: /,"");print}' "$spost")
      scat=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="category"{sub(/^[^:]*: /,"");print}' "$spost")
      stags=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="tags"{sub(/^[^:]*: /,"");print}' "$spost")
      simage=$(awk 'BEGIN{FS=": ";c=0} /^---$/{c++;next} c==1&&$1=="image"{sub(/^[^:]*: /,"");print}' "$spost")
    fi
    [ -z "$stitle" ] && stitle=$(grep '^# ' "$spost" | head -1 | sed 's/^# //')
    [ -z "$sdate" ] && echo "$sfilename" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' && sdate=$(echo "$sfilename" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')
    scontent=$(awk 'BEGIN{c=0} /^---$/{c++;next} c>=2{print}' "$spost" 2>/dev/null | escape_js_str)
    [ -z "$scontent" ] && scontent=$(cat "$spost" | escape_js_str)
    se_title=$(echo "$stitle" | sed 's/"/\\"/g')
    se_cat=$(echo "$scat" | sed 's/"/\\"/g')
    se_tags=$(echo "$stags" | sed 's/"/\\"/g')
    se_image=$(echo "$simage" | sed 's/"/\\"/g')
    echo -n '{"slug":"'"$sslug"'","title":"'"$se_title"'","date":"'"$sdate"'","category":"'"$se_cat"'","tags":"'"$se_tags"'","image":"'"$se_image"'","content":"'"$scontent"'"}' >> "$OUTPUT/post/${slug}.html"
  done
  echo "];" >> "$OUTPUT/post/${slug}.html"
  echo "const BLOGCV_CURRENT_POST = '${slug}';" >> "$OUTPUT/post/${slug}.html"

  cat >> "$OUTPUT/post/${slug}.html" << POSTTAIL
  </script>
</head>
<body>
  <div id="app" class="min-h-screen">
    <nav class="navbar bg-base-100/90 backdrop-blur-md shadow-sm sticky top-0 z-50">
      <div class="navbar-start"><a class="btn btn-ghost text-lg md:text-xl" href="../index.html">${SITE_TITLE}</a></div>
      <div class="navbar-end">
        <a class="btn btn-primary" href="../index.html#contact">Contactar</a>
      </div>
    </nav>
    <main class="min-h-screen bg-base-200 py-8">
      <article class="max-w-3xl mx-auto px-4">
        <a href="../index.html#blog" class="link link-hover text-sm opacity-70 hover:opacity-100 inline-flex items-center gap-1 mb-4"><i class="fa-solid fa-arrow-left"></i> Volver al blog</a>
        <h1 class="text-3xl md:text-4xl font-bold mt-2 fade-in">${e_title}</h1>
        <div class="flex flex-wrap gap-4 mt-4 text-sm opacity-70 fade-in">
          <span><i class="fa-regular fa-calendar mr-1"></i>${date}</span>
          <span><i class="fa-regular fa-clock mr-1"></i>${rt}</span>
          <span class="badge badge-primary badge-sm">${e_cat}</span>
        </div>
        <div class="flex flex-wrap gap-1 mt-3 fade-in">${tags_html}</div>
        ${toc_html}
        <div class="post-content mt-10 fade-in">${post_body_html}</div>
        <div class="divider mt-16"></div>
        <div class="flex flex-wrap items-center gap-3 mb-8 fade-in">
          <span class="text-sm font-semibold">Compartir:</span>
          <a href="https://twitter.com/intent/tweet?text=${e_title}&url=https%3A%2F%2F${USERNAME}.github.io%2Fpost%2F${slug}.html" target="_blank" rel="noopener" class="btn btn-ghost btn-sm btn-circle" aria-label="Compartir en X"><i class="fa-brands fa-x-twitter"></i></a>
          <a href="https://www.linkedin.com/sharing/share-offsite/?url=https%3A%2F%2F${USERNAME}.github.io%2Fpost%2F${slug}.html" target="_blank" rel="noopener" class="btn btn-ghost btn-sm btn-circle" aria-label="Compartir en LinkedIn"><i class="fa-brands fa-linkedin"></i></a>
          <a href="https://wa.me/?text=${e_title}%20https%3A%2F%2F${USERNAME}.github.io%2Fpost%2F${slug}.html" target="_blank" rel="noopener" class="btn btn-ghost btn-sm btn-circle" aria-label="Compartir en WhatsApp"><i class="fa-brands fa-whatsapp"></i></a>
        </div>
        <div class="text-center mb-12 fade-in">
          <a href="../index.html#blog" class="btn btn-outline btn-sm"><i class="fa-solid fa-arrow-left mr-1"></i> Ver más artículos</a>
          <a href="../index.html#contact" class="btn btn-primary btn-sm"><i class="fa-solid fa-envelope mr-1"></i> Contactar</a>
        </div>
      </article>
    </main>
    <footer class="footer footer-center p-6 bg-base-300 text-base-content"><aside><p class="text-sm">&copy; $(date +%Y) ${USERNAME_TITLE}. ${COPYRIGHT}</p></aside></footer>
  </div>
  <script src="../js/app.js"></script>
</body>
</html>
POSTTAIL

  POST_COUNT=$((POST_COUNT + 1))
done

echo ""

# =====================================================
# GENERATE GITHUB WORKFLOW
# =====================================================

#mkdir -p .github/workflows
#cat > .github/workflows/deploy.yml << EODEPLOY
#name: Deploy to GitHub Pages
#
#on:
#  push:
#    branches: ["main"]
#  workflow_dispatch:
#
#permissions:
#  contents: read
#  pages: write
#  id-token: write
#
#concurrency:
#  group: "pages"
#  cancel-in-progress: false
#
#jobs:
#  build:
#    runs-on: ubuntu-latest
#    steps:
#      - uses: actions/checkout@v4
#      - name: Install dependencies
#        run: |
#          sudo apt-get update
#          sudo apt-get install -y webp ffmpeg
#      - name: Build site
#        run: |
#          chmod +x build.sh
#          ./build.sh
#      - name: Setup Pages
#        uses: actions/configure-pages@v5
#        with:
#          path: ./public
#      - name: Upload artifact
#        uses: actions/upload-pages-artifact@v3
#        with:
#          path: ./public
#  deploy:
#    needs: build
#    runs-on: ubuntu-latest
#    environment:
#      name: github-pages
#      url: ${{ steps.deployment.outputs.page_url }}
#    steps:
#      - name: Deploy to GitHub Pages
#        id: deployment
#        uses: actions/deploy-pages@v4
#
#EODEPLOY
#
#echo "  [OK] GitHub workflow generado"
#echo ""

# =====================================================
# PROCESS IMAGES
# =====================================================

IMG_TOTAL=0
if [ -d "assets/images" ]; then
  for img in assets/images/*; do
    [ -f "$img" ] || continue
    ext="${img##*.}"; ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    base=$(basename "$img" ".${ext}"); base=$(basename "$base" ".${ext}")
    case "$ext" in
      jpg|jpeg|png|bmp|gif)
        out="$OUTPUT/img/${base}.webp"
        if command -v cwebp &>/dev/null; then
          cwebp -quiet "$img" -o "$out" 2>/dev/null && echo "  [IMG] ${base}.${ext} -> ${base}.webp"
        elif command -v convert &>/dev/null; then
          convert "$img" "$out" 2>/dev/null && echo "  [IMG] ${base}.${ext} -> ${base}.webp"
        else
          cp "$img" "$out"
          echo "  [IMG] ${base}.${ext} (copiado sin compresión)"
        fi
        IMG_TOTAL=$((IMG_TOTAL + 1)) ;;
      webp)
        cp "$img" "$OUTPUT/img/$(basename "$img")"
        IMG_TOTAL=$((IMG_TOTAL + 1)) ;;
      *)
        cp "$img" "$OUTPUT/img/$(basename "$img")"
        IMG_TOTAL=$((IMG_TOTAL + 1)) ;;
    esac
  done
fi

# =====================================================
# PROCESS VIDEOS
# =====================================================

VID_TOTAL=0
if [ -d "assets/videos" ]; then
  for video in assets/videos/*; do
    [ -f "$video" ] || continue
    filename=$(basename "$video")
    ext="${filename##*.}"
    if [ "$COMPRESS_VIDEO" = "true" ] && [ "$ext" = "mp4" ] && command -v ffmpeg &>/dev/null; then
      echo "  [VID] Comprimiendo: $filename"
      ffmpeg -i "$video" -vcodec libx264 -crf 28 -preset medium -y "$OUTPUT/video/${filename}" -loglevel error 2>/dev/null || \
      cp "$video" "$OUTPUT/video/${filename}"
    else
      cp "$video" "$OUTPUT/video/${filename}"
    fi
    VID_TOTAL=$((VID_TOTAL + 1))
  done
fi

# =====================================================
# COPY EXTRA FILES
# =====================================================

[ -d "assets/files" ] && cp assets/files/* "$OUTPUT/files/" 2>/dev/null || true

# =====================================================
# GENERATE SEO FILES
# =====================================================

cat > "$OUTPUT/robots.txt" << EOROBOT
User-agent: *
Allow: /
Sitemap: ${SITE_URL}sitemap.xml
EOROBOT

{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
  echo '  <url><loc>'"${SITE_URL}"'</loc><changefreq>monthly</changefreq><priority>1.0</priority></url>'
  for post in assets/posts/*.md; do
    [ -f "$post" ] || continue
    bname=$(basename "$post" .md)
    echo '  <url><loc>'"${SITE_URL}post/${bname}.html"'</loc><changefreq>monthly</changefreq><priority>0.8</priority></url>'
  done
  echo '</urlset>'
} > "$OUTPUT/sitemap.xml"

touch "$OUTPUT/.nojekyll"

echo "  [OK] robots.txt + sitemap.xml + .nojekyll generados"
echo ""

# =====================================================
# VERIFY OUTPUT FILES
# =====================================================

echo ""
echo "  [INFO] Verificando archivos generados..."

HTML_COUNT=0
verify_file() {
  if [ -f "$1" ]; then
    debug "  [OK] $1"
    HTML_COUNT=$((HTML_COUNT + 1))
  else
    error_out "Archivo requerido no encontrado: $1"
  fi
}

verify_file "$OUTPUT/index.html"
verify_file "$OUTPUT/css/main.css"
verify_file "$OUTPUT/js/app.js"
verify_file "$OUTPUT/robots.txt"
verify_file "$OUTPUT/sitemap.xml"

for post in assets/posts/*.md; do
  [ -f "$post" ] || continue
  bname=$(basename "$post" .md)
  verify_file "$OUTPUT/post/${bname}.html"
done

echo "  [OK] Todos los archivos requeridos existen"
echo ""

# =====================================================
# SUMMARY
# =====================================================

echo "=============================================="
echo "  VALIDACION COMPLETADA"
echo "=============================================="
echo "  JSON cargados correctamente:    6"
echo "  Comunidades:                    ${TOTAL_COMMUNITIES}"
echo "  Actividades:                    ${TOTAL_ACTIVITIES}"
echo "  Experiencias laborales:         ${TOTAL_JOBS}"
echo "  Proyectos:                      ${TOTAL_PROJECTS}"
echo "  Posts:                          ${POST_COUNT}"
echo "  Redes sociales:                 ${TOTAL_CONTACTS}"
echo "----------------------------------------------"
echo "  Imagenes convertidas:           ${IMG_TOTAL}"
echo "  Videos procesados:              ${VID_TOTAL}"
echo "  Archivos HTML generados:        ${HTML_COUNT}"
echo "----------------------------------------------"
echo "  Errores:                        ${ERR_COUNT}"
echo "  Advertencias:                   ${WARN_COUNT}"
echo "----------------------------------------------"

if [ "$TOTAL_PROJECTS" -eq 0 ] && [ "$SHOW_PROJECTS" != "false" ]; then
  warn "No se encontraron proyectos habilitados"
fi
if [ "$TOTAL_JOBS" -eq 0 ] && [ "$SHOW_JOBS" != "false" ]; then
  warn "No se encontraron experiencias laborales habilitadas"
fi
if [ "$TOTAL_COMMUNITIES" -eq 0 ] && [ "$SHOW_COMMUNITIES" != "false" ]; then
  warn "No se encontraron comunidades habilitadas"
fi
if [ "$TOTAL_CONTACTS" -eq 0 ] && [ "$SHOW_CONTACT" != "false" ]; then
  warn "No se encontraron contactos habilitados"
fi
if [ "$POST_COUNT" -eq 0 ]; then
  warn "No se encontraron publicaciones Markdown"
fi

if [ "$ERR_COUNT" -eq 0 ] && [ "$WARN_COUNT" -eq 0 ]; then
  echo "=============================================="
  echo "  GENERACION EXITOSA"
  echo "=============================================="
elif [ "$ERR_COUNT" -eq 0 ]; then
  echo "=============================================="
  echo "  GENERACION COMPLETADA CON ADVERTENCIAS"
  echo "=============================================="
fi
echo ""
echo "  Output: $(cd "$OUTPUT" && pwd)"
echo "  Abre public/index.html en tu navegador"
echo ""
