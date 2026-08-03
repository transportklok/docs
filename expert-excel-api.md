---
title: Expert Excel API-integratie
description: OAuth- en REST-documentatie voor de Expert Excel-koppeling met TransportKlok.
---

# Expert Excel API-integratie

Deze documentatie beschrijft hoe `expertexcel.nl` met TransportKlok verbindt. De integratie gebruikt OAuth 2.0 voor gebruikersautorisatie en REST API v1 voor het lezen van organisaties en werknemers en het aanmaken, volgen en downloaden van exports.

## 1. Integratie in het kort

De Expert Excel-app is een single-organization-integratie. Tijdens de OAuth-autorisatie kiest de gebruiker één organisatie. Het OAuth-token kan daarna alleen binnen die organisatie worden gebruikt.

De app krijgt deze scopes:

| Scope | Gebruik |
| --- | --- |
| `organizations:read` | Organisaties lezen |
| `workers:read` | Werknemers lezen |
| `exports:*` | Exports lezen, starten en downloaden |

De app mag zelf geen organisatie-id gebruiken om toegang tot een andere organisatie te verkrijgen. Een organisatie die niet aan het token is gekoppeld, valt buiten de toegestane gegevensgrens.

## 2. Gegevens die de ontwikkelaar nodig heeft

Voor iedere omgeving ontvangt de integratieontwikkelaar:

| Waarde | Betekenis |
| --- | --- |
| `client_id` | Het geregistreerde OAuth-client-id van Expert Excel |
| `client_secret` | Geheim voor een server-side OAuth-client; nooit in frontendcode plaatsen |
| `redirect_uri` | De exacte callback-URL van Expert Excel |
| `api_base_url` | De basis-URL van de betreffende TransportKlok-omgeving |

De `redirect_uri` moet exact overeenkomen met de URL die voor de OAuth-client is geregistreerd. Wildcards en willekeurige redirect-URL’s zijn niet toegestaan.

De REST API-basisroute is:

```text
{api_base_url}/api/rest/v1
```

## 3. OAuth 2.0-autorisatie

Gebruik de Authorization Code-flow met PKCE en `S256` als `code_challenge_method`.

### 3.1 PKCE-waarden maken

De Expert Excel-server maakt een cryptografisch willekeurige `code_verifier`, de bijbehorende Base64URL-gecodeerde SHA-256 `code_challenge` en een cryptografisch willekeurige `state`.

Bewaar `code_verifier` en `state` tijdelijk aan de serverkant. Controleer bij de callback dat de ontvangen `state` gelijk is aan de opgeslagen waarde.

### 3.2 Gebruiker naar TransportKlok sturen

```text
GET {api_base_url}/oauth/authorize
    ?client_id={client_id}
    &redirect_uri={url_encoded_redirect_uri}
    &response_type=code
    &scope=organizations%3Aread%20workers%3Aread%20exports%3A%2A
    &state={state}
    &code_challenge={code_challenge}
    &code_challenge_method=S256
```

De gebruiker logt in, kiest één organisatie en keurt de gevraagde scopes goed. Bij weigering of een ongeldige aanvraag volgt een OAuth-fout naar de redirect-URL. Verwerk `error`, `error_description` en `state` veilig.

### 3.3 Authorization code omwisselen

Na goedkeuring ontvangt de callback bijvoorbeeld:

```text
{redirect_uri}?code={authorization_code}&state={state}
```

Wissel de code server-side om voor tokens:

```http
POST {api_base_url}/oauth/token
Content-Type: application/x-www-form-urlencoded
Accept: application/json
```

```text
grant_type=authorization_code
client_id={client_id}
client_secret={client_secret}
redirect_uri={redirect_uri}
code={authorization_code}
code_verifier={code_verifier}
```

Voor een public client laat je `client_secret` weg. De `code_verifier` blijft bij PKCE verplicht.

Voorbeeldresponse:

```json
{
  "token_type": "Bearer",
  "expires_in": 3600,
  "access_token": "...",
  "refresh_token": "..."
}
```

Sla access- en refresh-tokens versleuteld op. Geef tokens niet door aan de browser als dat met een server-side integratie kan worden voorkomen.

### 3.4 Access-token vernieuwen

```http
POST {api_base_url}/oauth/token
Content-Type: application/x-www-form-urlencoded
Accept: application/json
```

```text
grant_type=refresh_token
client_id={client_id}
client_secret={client_secret}
refresh_token={refresh_token}
```

Gebruik het nieuwe refresh-token als TransportKlok dat terugstuurt. Behandel het oude refresh-token daarna als vervangen.

## 4. REST API-conventies

### 4.1 Headers

Stuur bij iedere API-aanvraag het access-token mee:

```http
Authorization: Bearer {access_token}
Accept: application/json
```

Gebruik bij requests met een JSON-body ook `Content-Type: application/json`.

### 4.2 Identifiers en responses

De REST API gebruikt UUID’s voor organisatie-, werknemer- en export-id’s.

Een succesvolle detailresponse heeft deze vorm:

```json
{
  "data": {
    "id": "..."
  }
}
```

Een succesvolle lijstresponse bevat een `data`-array en paginator-metadata, zoals `current_page`, `per_page`, `total`, `last_page`, `from`, `to` en navigatielinks.

### 4.3 Algemene lijstparameters

De lijst-endpoints voor organisaties, werknemers en exports ondersteunen:

| Parameter | Type | Standaard | Uitleg |
| --- | --- | --- | --- |
| `limit` | integer, 1–100 | `15` | Aantal records per pagina |
| `order_identifier` | string | `id` | Veld waarop wordt gesorteerd |
| `order_direction` | `asc`, `desc`, `random` | `asc` | Sorteervolgorde |

Gebruik voor paginering de `data`-array en de paginator-metadata uit de response. Er zijn op dit moment geen algemene domeinfilters voor naam, status, datum of werknemer actief. `order_identifier` is sortering, geen filter.

De response gebruikt de vaste algemene publieke gegevensset. Relaties kunnen niet via queryparameters worden toegevoegd en het publiciteitsniveau kan niet worden aangepast.

## 5. Endpoint-overzicht

| Onderdeel | Endpoint | Scope |
| --- | --- | --- |
| Organisaties | `GET /organizations` | `organizations:read` |
| Organisatie | `GET /organizations/{organization_id}` | `organizations:read` |
| Werknemers | `GET /organizations/{organization_id}/workers` | `workers:read` |
| Werknemer | `GET /organizations/{organization_id}/workers/{worker_id}` | `workers:read` |
| Exports starten | `POST /organizations/{organization_id}/exports` | `exports:*` |
| Exports ophalen | `GET /organizations/{organization_id}/exports` | `exports:*` |
| Exportstatus | `GET /organizations/{organization_id}/exports/{export_id}` | `exports:*` |
| Exportbestand downloaden | `GET /organizations/{organization_id}/exports/{export_id}/download` | `exports:*` |

Alle routes staan onder `{api_base_url}/api/rest/v1`.

## 6. Organisaties

### 6.1 Organisaties ophalen

```http
GET /api/rest/v1/organizations
```

Scope: `organizations:read`

Geeft de organisatie terug die aan het OAuth-token is toegekend. Omdat Expert Excel single-organization is, bevat de lijst normaal gesproken één record.

Voorbeeldresponse:

```json
{
  "data": [
    {
      "id": "4c1d...",
      "name": "Transportbedrijf Voorbeeld"
    }
  ],
  "current_page": 1,
  "per_page": 15,
  "total": 1
}
```

### 6.2 Eén organisatie ophalen

```http
GET /api/rest/v1/organizations/{organization_id}
```

Scope: `organizations:read`

De `organization_id` moet zowel bij de gebruiker horen als door het OAuth-token zijn toegekend. Een niet-toegekende organisatie resulteert in `404 Not Found`.

Het algemene organisatiemodel bevat minimaal de publieke organisatiegegevens, waaronder `id`, `name` en — indien geconfigureerd — `collective_labour_agreement_id`.

## 7. Werknemers

### 7.1 Werknemers ophalen

```http
GET /api/rest/v1/organizations/{organization_id}/workers
```

Scope: `workers:read`

Geeft de werknemers binnen de toegekende organisatie terug. De query is altijd organisatiegebonden; werknemers uit andere organisaties worden niet teruggegeven.

Voorbeeld van de algemene werknemerdata:

```json
{
  "id": "8b21...",
  "user_id": null,
  "name": "Jansen, Jan",
  "formal_name": "J. Jan Jansen",
  "employment_number": "W-1001",
  "initials": "J.J.",
  "first_name": "Jan",
  "preposition": null,
  "last_name": "Jansen",
  "profile_photo_url": "https://..."
}
```

Gevoelige velden, zoals `meta`, worden niet gepubliceerd. Gebruik `id` als stabiele synchronisatiesleutel. `employment_number` kan als bedrijfsreferentie worden gebruikt wanneer die is gevuld.

### 7.2 Eén werknemer ophalen

```http
GET /api/rest/v1/organizations/{organization_id}/workers/{worker_id}
```

Scope: `workers:read`

Geeft één werknemer binnen de organisatiecontext terug. Een werknemer buiten de organisatiecontext resulteert in `404 Not Found`.

## 8. Exports

Een export verloopt asynchroon:

1. Start een export met `POST`.
2. Bewaar het teruggegeven export-id.
3. Vraag de exportstatus op met `GET`.
4. Download het bestand zodra de status `success` is.

### 8.1 Export starten

```http
POST /api/rest/v1/organizations/{organization_id}/exports
Authorization: Bearer {access_token}
Accept: application/json
Content-Type: application/json
```

Scope: `exports:*`

Requestvelden:

| Veld | Verplicht | Uitleg |
| --- | --- | --- |
| `name` | Ja | Interne naam van het geregistreerde exporttype; geen vrije bestandsnaam |
| `format` | Nee | `xlsx`, `csv` of `json`; zonder deze parameter geldt de organisatie-instelling |
| overige velden | Exporttype-afhankelijk | Bijvoorbeeld `filter` voor de productieve tijdregistratie-data-export |

De REST-laag valideert generiek alleen dat `name` een verplichte string van maximaal 255 tekens is. De benodigde overige parameters zijn afhankelijk van het gekozen exporttype.

Voorbeeld voor de productieve tijdregistratie-data-export:

```json
{
  "name": "productive-time-registrations-data",
  "format": "json",
  "filter": {
    "period": ["2026-07-01", "2026-07-31"]
  }
}
```

`format` overschrijft alleen voor deze REST-export de organisatie-instelling. JSON is niet beschikbaar als keuze in de applicatieconfiguratie; daar blijven Excel en CSV de configureerbare opties.

Een succesvolle aanvraag maakt een exportjob aan. De job kan nog in status `created` of `running` staan:

```json
{
  "data": {
    "id": "f912...",
    "name": "productive-time-registrations-data",
    "status": "created",
    "progress": 0,
    "message": null,
    "downloaded_at": null,
    "created_at": "2026-07-29T10:00:00+00:00",
    "updated_at": "2026-07-29T10:00:00+00:00"
  }
}
```

### 8.2 Exports van een organisatie ophalen

```http
GET /api/rest/v1/organizations/{organization_id}/exports
```

Scope: `exports:*`

Geeft de exports van de organisatie terug. Gebruik de algemene lijstparameters voor paginering en sortering.

### 8.3 Exportstatus ophalen

```http
GET /api/rest/v1/organizations/{organization_id}/exports/{export_id}
```

Scope: `exports:*`

Gebruik minimaal deze velden om de export te volgen:

| Veld | Betekenis |
| --- | --- |
| `id` | Export-id |
| `name` | Geregistreerd exporttype |
| `status` | Bijvoorbeeld `created`, `running`, `success` of `failed` |
| `progress` | Voortgangspercentage |
| `message` | Fout- of statusmelding, indien aanwezig |
| `downloaded_at` | Tijdstip waarop het bestand is gedownload, indien aanwezig |
| `created_at` | Aanmaaktijdstip |
| `updated_at` | Tijdstip van laatste wijziging |

`storage_path`, `organization_id` en de interne auto-delete-instelling zijn geen publieke exportvelden.

### 8.4 Exportbestand downloaden

```http
GET /api/rest/v1/organizations/{organization_id}/exports/{export_id}/download
```

Scope: `exports:*`

Bij een geslaagde export geeft dit endpoint het bestand terug als downloadresponse. Het bestand kan pas worden gedownload wanneer de export is afgerond en het bestand bestaat.

Bij een nog niet afgeronde of mislukte export volgt geen bestand. Behandel `404 Not Found` als “nog niet beschikbaar” of “niet beschikbaar” en controleer daarna de exportstatus.

Een succesvolle download zet `downloaded_at` op de export.

### 8.5 Voorbeeldexport: productieve tijdregistratie-data

Voor Expert Excel is de relevante export:

```text
productive-time-registrations-data
```

De `period`-filter is inclusief en bevat twee datums:

```json
{
  "filter": {
    "period": ["2026-07-01", "2026-07-31"]
  }
}
```

Zonder periode wordt de volledige beschikbare periode gebruikt. Voor Expert Excel is het aan te raden altijd een periode mee te geven.

De vaste exportkolommen zijn:

```text
organisatie
team
voornaam
tussenvoegsel
achternaam
referentie
datum
start
eind
totaal_uren
netto_uren
controleur
status
aangemaakt_op
gewijzigd_op
```

Daarnaast kunnen dynamische kolommen worden toegevoegd voor productieve activiteiten, tijdregistratie-attributen en versie-attributen. De exacte kolommen zijn afhankelijk van de configuratie van de organisatie.

Bij `format: "json"` wordt het gedownloade bestand een JSON-array. Iedere rij is een object waarvan de keys overeenkomen met de exportkolommen:

```json
[
  {
    "organisatie": "Transportbedrijf Voorbeeld",
    "team": "Planning",
    "voornaam": "Jan",
    "datum": "2026-07-01",
    "start": "08:00",
    "eind": "16:30",
    "totaal_uren": 8.5,
    "netto_uren": 8.0,
    "status": "approved"
  }
]
```

## 9. Foutafhandeling

| HTTP-status | Betekenis |
| --- | --- |
| `400` | Ongeldige OAuth- of requestparameters |
| `401` | Geen, verlopen of ongeldig access-token |
| `403` | Token heeft de benodigde scope niet |
| `404` | Record bestaat niet of valt buiten de toegekende organisatiecontext |
| `422` | Validatiefout in de requestbody, bijvoorbeeld een ongeldig `format` |
| `429` | Rate limit; opnieuw proberen met backoff |
| `5xx` | Tijdelijke serverfout; opnieuw proberen met begrensde backoff |

Maak bij `401` eerst een nieuw access-token met het refresh-token. Herhaal een request niet onbeperkt. Gebruik idempotency- of deduplicatielogica aan de Expert Excel-kant voor het starten van exports, omdat een timeout kan optreden nadat TransportKlok de export al heeft aangemaakt.

## 10. Aanbevolen synchronisatievolgorde

1. Autoriseer de gebruiker en sla de gekozen organisatie-id op.
2. Haal de organisatie op en controleer de verbinding.
3. Synchroniseer werknemers met `worker_id` als stabiele sleutel.
4. Start alleen de benodigde exporttypes.
5. Poll de exportstatus met een oplopende wachttijd.
6. Download het bestand zodra `status` `success` is.
7. Bewaar het export-id en de downloadtijd voor audit en deduplicatie.

## 11. Contractbeperkingen

- De Expert Excel-client is single-organization. Voor een tweede organisatie is een aparte autorisatie nodig.
- De API biedt op dit moment geen algemeen endpoint om alle beschikbare exporttypes en hun parameters op te vragen.
- Exportnamen en exportparameters moeten daarom vooraf met de TransportKlok-beheerder worden afgestemd.
- Het geneste endpoint voor engagementen bestaat technisch, maar valt niet binnen de afgesproken Expert Excel-rechten en moet niet worden gebruikt.
- De `organizations:read`-controle moet op de organisatieroutes expliciet worden afgedwongen voordat de koppeling productiegebruik krijgt.

## 12. Lokale testchecklist

- Test OAuth-login met een geverifieerde gebruiker.
- Controleer dat de gebruiker precies één organisatie kiest.
- Controleer dat `state` en PKCE `code_verifier` worden gevalideerd.
- Test token exchange en refresh.
- Test dat een andere organisatie `404` geeft.
- Test `403` bij ontbrekende scopes.
- Test `format` zonder waarde, met `xlsx`, `csv` en `json`, en met een ongeldige waarde.
- Test exportstatussen `created`, `running`, `success` en `failed`.
- Test een download vóór en na voltooiing van de export.
- Test timeouts, `401`, `404`, `422`, `429` en tijdelijke `5xx`-fouten.
