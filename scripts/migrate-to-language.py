#!/usr/bin/env python3
"""Move every docs page under a language folder with its English path and generate the redirects.

Usage: scripts/migrate-to-language.py [root] [language]

The old path of a page is mapped segment by segment with SEGMENTS, with the page-level exceptions in PAGES.
Pages that already have an English path keep it and only gain the language prefix. The docs.json navigation moves
under navigation.languages, internal links are rewritten, and every page that was published under an old path gets a
permanent redirect, as does every redirect docs.json already had.
"""
import json
import os
import re
import sys

SEGMENTS = {
    'beheerders': 'management', 'medewerkers': 'workforce',
    'wagenparkbeheer': 'fleet-management', 'personeelszaken': 'human-resources', 'urenbeheer': 'hour-management',
    'klantenbeheer': 'customer-management', 'instellingen': 'settings', 'werk': 'hour-management',
    'kaart': 'map', 'voertuigen': 'vehicles', 'locaties': 'locations', 'telematica': 'telematics',
    'druppels': 'beacons', 'tachograaf': 'tachograph', 'bestuurders': 'drivers', 'bedrijfskaarten': 'company-cards',
    'koppelingen': 'integrations', 'personeel': 'workers', 'uitnodigingen': 'invitations',
    'salariskoppelingen': 'payroll-integrations', 'salarisrondes': 'payroll-runs',
    'aanvullingen-inhoudingen': 'payroll-components', 'tijdregistratie': 'time-registrations',
    'salarismutatie-export': 'payroll-mutation-export', 'opdrachtgevers': 'customers',
    'overzicht': 'overview', 'aanmaken': 'create', 'bewerken': 'edit', 'wijzigen': 'edit', 'tijdlijn': 'timeline',
    'koppelen': 'connect', 'verwerken': 'process', 'correcties': 'corrections', 'organisatie': 'organization',
    'inloggen': 'login', 'pushmeldingen': 'push-notifications', 'thuis': 'home', 'werk-registreren': 'register-work',
    'verlof-registreren': 'register-leave', 'organisaties': 'organizations', 'storingen': 'malfunctions',
}

# Account, organisation and team settings sit beside the settings pages that already have English paths.
PAGES = {
    'beheerders/instellingen/organisatie/beheerders': 'settings/organization/administrators',
    'beheerders/instellingen/organisatie/teams': 'settings/organization/teams',
    'beheerders/instellingen/organisatie/notificaties': 'settings/organization/notifications',
    'beheerders/instellingen/organisatie/abonnement': 'settings/organization/subscription',
    'beheerders/instellingen/team/kenmerken': 'settings/team/attributes',
    'beheerders/instellingen/team/werkpatronen': 'settings/team/work-patterns',
    'beheerders/instellingen/team/werkzaamheden': 'settings/team/activities',
    'beheerders/instellingen/account/profiel': 'settings/user/profile',
    'beheerders/instellingen/account/weergave': 'settings/user/appearance',
    'beheerders/instellingen/account/apps': 'settings/user/apps',
    'beheerders/instellingen/account/organisaties-en-teams': 'settings/user/memberships',
    'medewerkers/app/instellingen': 'workforce/app/settings',
}

# Top-level folders and pages that were published before the restructuring and so need redirects.
PUBLISHED_ROOTS = ('beheerders/', 'medewerkers/', 'api/')

SKIP_DIRS = {'scripts', 'snippets', 'node_modules', 'images', 'logo'}


def english(path):
    """Return the English path of a page path."""
    if path in PAGES:
        return PAGES[path]
    return '/'.join(SEGMENTS.get(segment, segment) for segment in path.split('/'))


def pages_under(root):
    """List the page paths (without .mdx) under the root, skipping tooling folders."""
    found = []
    for folder, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in SKIP_DIRS]
        for name in names:
            if name.endswith('.mdx'):
                found.append(os.path.relpath(os.path.join(folder, name[:-4]), root))
    return sorted(found)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    language = sys.argv[2] if len(sys.argv) > 2 else 'nl'
    pages = pages_under(root)
    moves = {page: language + '/' + english(page) for page in pages}

    if len(set(moves.values())) != len(moves):
        sys.exit('two pages map to one path')

    def new_url(url):
        """Map a link target to its new URL, or None when it is not a page."""
        path, anchor = re.match(r'^([^#?]*)(.*)$', url).groups()
        key = path.strip('/')
        if key == '':
            return '/' + language + '/index' + anchor
        return '/' + moves[key] + anchor if key in moves else None

    link = re.compile(r'(\]\(|href=")(/[^)"\s]*)')

    def rewrite(match):
        target = new_url(match.group(2))
        return match.group(1) + (target or match.group(2))

    for page, target in moves.items():
        text = open(os.path.join(root, page + '.mdx'), encoding='utf-8').read()
        os.makedirs(os.path.dirname(os.path.join(root, target + '.mdx')), exist_ok=True)
        os.replace(os.path.join(root, page + '.mdx'), os.path.join(root, target + '.mdx'))
        open(os.path.join(root, target + '.mdx'), 'w', encoding='utf-8').write(link.sub(rewrite, text))

    for folder, dirs, _ in os.walk(root, topdown=False):
        if folder != root and not os.listdir(folder):
            os.rmdir(folder)

    config_path = os.path.join(root, 'docs.json')
    config = json.load(open(config_path, encoding='utf-8'))

    def move_nav(node):
        if isinstance(node, str):
            return moves.get(node, node)
        if isinstance(node, list):
            return [move_nav(item) for item in node]
        return {key: move_nav(value) for key, value in node.items()}

    tabs = move_nav(config['navigation']['tabs'])
    config['navigation'] = {'languages': [{'language': language, 'default': True, 'tabs': tabs}]}

    redirects = []
    seen = set()

    def redirect(source, destination):
        if source != destination and source not in seen:
            seen.add(source)
            redirects.append({'source': source, 'destination': destination, 'permanent': True})

    for old in config.get('redirects', []):
        destination = new_url(old['destination']) or old['destination']
        redirect(old['source'], destination)
    redirect('/', '/' + language + '/index')
    for page in pages:
        if page == 'index' or page.startswith(PUBLISHED_ROOTS):
            redirect('/' + page, '/' + moves[page])
    config['redirects'] = redirects

    open(config_path, 'w', encoding='utf-8').write(json.dumps(config, indent=2, ensure_ascii=False) + '\n')
    print(len(moves), 'pages moved,', len(redirects), 'redirects')


main()
