<script>
  import electionsData from './directory.json';

  let district = '';
  let boundaries = '1';
  let countyBorders = '1';
  let isolate = '0';
  let interactive = '1';
  let height = '600';
  let hed = '';
  let chatter = '';
  let showtext = '0';
  let clicky = '1';
  let elections = electionsData.races;

  const baseUrl = 'https://static.startribune.com/news/projects/all/elex26_general/index.html';

  $: selectedRace = elections.find((e) => String(e.index) === String(district));
  $: shading = selectedRace?.shade ?? '0';
  // Statewide races (district "0") have no district borders to draw
  $: statewide = selectedRace ? String(selectedRace.district) === '0' : false;

  // Per-race defaults, applied when a contest is picked; they can still be
  // changed after. Congressional and county races open isolated on their
  // district or county, without the state/metro zoom shortcuts.
  function applyRaceDefaults(index) {
    const race = elections.find((e) => String(e.index) === String(index));
    const congressional = race?.overlay === 'congress2022.json';
    const county = race?.overlay === 'counties.json' && String(race.district) !== '0';
    const isolated = congressional || county;
    isolate = isolated ? '2' : '0';
    interactive = isolated ? '0' : '1';
  }

  // Reactively rebuild the draft URL any time a param changes
  $: draftUrl = (() => {
    const params = new URLSearchParams({
      office: district,
      overlay: statewide ? '0' : boundaries,
      counties: countyBorders,
      filter: isolate,
      interactive,
      shading,
      title: hed,
      chatter,
      height,
      text: showtext,
      clicky
    }).toString();
    return `${baseUrl}?${params}`;
  })();

  // The URL actually loaded into the preview/URL box, only updated on Generate
  let mapUrl = '';
  let generatedRace = null;

  function generate() {
    mapUrl = draftUrl;
    generatedRace = selectedRace;
  }

  let copied = false;
  async function copyUrl() {
    try {
      await navigator.clipboard.writeText(mapUrl);
      copied = true;
      setTimeout(() => (copied = false), 1500);
    } catch (e) {
      // clipboard API unavailable, ignore
    }
  }
</script>

<main>
  <header>
    <h1>StribLab General Election 2026 Mapifier</h1>
    <p>Pick a race and map settings, then click Generate to build a preview and shareable URL.</p>
    <p class="disclaimer">Internal use only. Don't share generated links publicly; embed on article pages instead.</p>
  </header>

  <div class="layout">
    <div class="preview-pane">
      <div class="preview-frame" style="height: {height}px;">
        {#if mapUrl !== ''}
          <iframe title="Map preview" src={mapUrl}></iframe>
        {:else}
          <div class="empty-state">Select a contest and click Generate to see a preview</div>
        {/if}
      </div>

      <div class="generate-row">
        <button type="button" class="generate-btn" on:click={generate} disabled={district === ''}>Generate</button>
        {#if mapUrl !== '' && mapUrl !== draftUrl}
          <span class="pending-hint">Settings changed — click Generate to update the preview</span>
        {/if}
      </div>

      <div class="url-box">
        <label for="urlOut">Generated URL</label>
        <div class="url-row">
          <input id="urlOut" type="text" readonly value={mapUrl} on:focus={(e) => e.target.select()} />
          <button type="button" on:click={copyUrl} disabled={mapUrl === ''}>{copied ? 'Copied!' : 'Copy'}</button>
        </div>
      </div>

      {#if generatedRace}
        <div class="data-links">
          <label>Underlying data files</label>
          <div class="data-links-row">
            {#if generatedRace.precincts}
              <a href={generatedRace.precincts} target="_blank" rel="noopener">GeoJSON</a>
            {/if}
            {#if generatedRace.csv}
              <a href={generatedRace.csv} target="_blank" rel="noopener">CSV</a>
            {/if}
          </div>
        </div>
      {/if}
    </div>

    <div class="controls-pane">
      <div class="field">
        <label for="eOffice">Contest</label>
        <select bind:value={district} id="eOffice" on:change={(e) => applyRaceDefaults(e.currentTarget.value)}>
          <option value="">— Select —</option>
          {#each elections as election}
            <option value={election.index}>{election.name}</option>
          {/each}
        </select>
      </div>

      <div class="field">
        <label>County borders</label>
        <div class="options">
          <label><input type="radio" value="1" bind:group={countyBorders} /> Enable</label>
          <label><input type="radio" value="0" bind:group={countyBorders} /> Disable</label>
        </div>
      </div>

      <div class="field">
        <label>District borders</label>
        <div class="options" class:disabled={statewide}>
          <label><input type="radio" value="1" bind:group={boundaries} disabled={statewide} /> Enable</label>
          <label><input type="radio" value="0" bind:group={boundaries} disabled={statewide} /> Disable</label>
        </div>
        {#if statewide}
          <p class="field-hint">Statewide races have no districts.</p>
        {/if}
      </div>

      <div class="field">
        <label>Zoom focus</label>
        <select bind:value={isolate}>
          <option value="0">State</option>
          <option value="1">Metro</option>
          <option value="2">Isolate districts</option>
          <option value="3">Large map</option>
          <option value="4">Hennepin County</option>
          <option value="5">Duluth</option>
          <option value="6">St. Cloud</option>
          <option value="7">Moorhead</option>
          <option value="8">Mankato</option>
          <option value="9">Rochester</option>
        </select>
      </div>

      <div class="field">
        <label>State/metro zoom shortcuts</label>
        <div class="options">
          <label><input type="radio" value="1" bind:group={interactive} /> Enable</label>
          <label><input type="radio" value="0" bind:group={interactive} /> Disable</label>
        </div>
      </div>

      <div class="field">
        <label>Map interactivity (zoom/pan/click/tooltips)</label>
        <div class="options">
          <label><input type="radio" value="1" bind:group={clicky} /> Enable</label>
          <label><input type="radio" value="0" bind:group={clicky} /> Disable</label>
        </div>
      </div>

      <div class="field">
        <label>Header text (hed/chatter)</label>
        <div class="options">
          <label><input type="radio" value="1" bind:group={showtext} /> Enable</label>
          <label><input type="radio" value="0" bind:group={showtext} /> Disable</label>
        </div>
      </div>

      <div class="field">
        <label for="eHed">Dataviz hed text</label>
        <input id="eHed" type="text" maxlength="255" bind:value={hed} />
      </div>

      <div class="field">
        <label for="eChatter">Dataviz chatter text</label>
        <textarea id="eChatter" bind:value={chatter}></textarea>
      </div>

      <div class="field">
        <label for="eHeight">Map height (px)</label>
        <input id="eHeight" type="text" maxlength="255" bind:value={height} />
      </div>
    </div>
  </div>
</main>

<style>
  :root {
    --accent: #1e7042;
    --border: #d8d8d8;
    --bg-panel: #f7f7f7;
  }

  main {
    font-family: "Lucida Grande", Tahoma, Arial, Verdana, sans-serif;
    max-width: 1200px;
    margin: 0 auto;
    padding: 24px 20px 60px;
    color: #222;
  }

  header h1 {
    font-size: 1.6rem;
    font-weight: 500;
    margin: 0 0 6px;
  }

  header p {
    margin: 0 0 4px;
    font-size: 0.9rem;
    color: #444;
  }

  .disclaimer {
    color: #c0392b;
  }

  .layout {
    display: grid;
    grid-template-columns: minmax(0, 1.6fr) minmax(280px, 1fr);
    gap: 24px;
    margin-top: 20px;
    align-items: start;
  }

  @media (max-width: 900px) {
    .layout {
      grid-template-columns: 1fr;
    }
  }

  .preview-frame {
    width: 100%;
    border: 1px solid var(--border);
    border-radius: 8px;
    overflow: hidden;
    background: #fff;
  }

  .preview-frame iframe {
    width: 100%;
    height: 100%;
    border: 0;
  }

  .empty-state {
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: #999;
    font-size: 0.9rem;
  }

  .generate-row {
    margin-top: 14px;
    display: flex;
    align-items: center;
    gap: 12px;
    flex-wrap: wrap;
  }

  .generate-btn {
    padding: 9px 18px;
    background: var(--accent);
    color: #fff;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-size: 0.9rem;
    font-weight: 700;
  }

  .generate-btn:hover:not(:disabled) {
    opacity: 0.9;
  }

  .generate-btn:disabled {
    background: #aaa;
    cursor: not-allowed;
  }

  .pending-hint {
    font-size: 0.8rem;
    color: #b5651d;
  }

  .url-box {
    margin-top: 14px;
  }

  .data-links {
    margin-top: 14px;
  }

  .data-links label {
    display: block;
    font-size: 0.8rem;
    font-weight: 700;
    margin-bottom: 4px;
  }

  .data-links-row {
    display: flex;
    gap: 14px;
  }

  .data-links-row a {
    color: var(--accent);
    font-size: 0.85rem;
    font-weight: 600;
    text-decoration: none;
  }

  .data-links-row a:hover {
    text-decoration: underline;
  }

  .url-box label {
    display: block;
    font-size: 0.8rem;
    font-weight: 700;
    margin-bottom: 4px;
  }

  .url-row {
    display: flex;
    gap: 8px;
  }

  .url-row input {
    flex: 1;
    font-family: monospace;
    font-size: 0.8rem;
    padding: 8px;
    border: 1px solid var(--border);
    border-radius: 6px;
    background: #fafafa;
  }

  .url-row button {
    padding: 8px 14px;
    background: var(--accent);
    color: #fff;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    font-size: 0.85rem;
  }

  .url-row button:hover {
    opacity: 0.9;
  }

  .url-row button:disabled {
    background: #aaa;
    cursor: not-allowed;
  }

  .controls-pane {
    background: var(--bg-panel);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 18px;
  }

  .field {
    margin-bottom: 16px;
  }

  .field:last-child {
    margin-bottom: 0;
  }

  .field label {
    display: block;
    font-size: 0.8rem;
    font-weight: 700;
    margin-bottom: 6px;
    color: #333;
  }

  .field select,
  .field input[type="text"],
  .field textarea {
    width: 100%;
    box-sizing: border-box;
    padding: 6px 8px;
    border: 1px solid #bbb;
    border-radius: 4px;
    font-size: 0.85rem;
    font-family: inherit;
  }

  .field textarea {
    min-height: 60px;
    resize: vertical;
  }

  .options {
    display: flex;
    gap: 16px;
    flex-wrap: wrap;
  }

  .options label {
    display: flex;
    align-items: center;
    gap: 5px;
    font-weight: 400;
    font-size: 0.85rem;
    margin: 0;
  }

  .options input[type="radio"] {
    margin: 0;
  }

  .options.disabled label {
    color: #999;
  }

  .field-hint {
    margin: 4px 0 0;
    font-size: 0.75rem;
    color: #888;
  }
</style>