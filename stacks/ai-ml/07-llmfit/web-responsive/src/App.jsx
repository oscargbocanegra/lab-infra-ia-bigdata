import { useState } from 'react';
import { FilterProvider } from './contexts/FilterContext';
import { I18nProvider, useI18n } from './contexts/I18nContext';
import { ModelProvider, useModelContext } from './contexts/ModelContext';
import { useModels } from './hooks/useModels';
import { useSystem } from './hooks/useSystem';
import Header from './components/Header';
import SystemPanel from './components/SystemPanel';
import FilterBar from './components/FilterBar';
import ModelTable from './components/ModelTable';
import DetailPanel from './components/DetailPanel';
import ComparePanel from './components/ComparePanel';

function DataLoader() {
  useModels();
  useSystem();
  return null;
}

function ModelsSection({ showFilters, showDetails }) {
  const { t } = useI18n();
  const { compareList, clearCompare, returned, total } = useModelContext();
  const [showCompare, setShowCompare] = useState(false);
  const compareCount = compareList.length;

  function closeCompare() {
    setShowCompare(false);
    clearCompare();
  }

  return (
    <section className="panel models-panel">
      <div className="panel-heading">
        <div>
          <p className="section-kicker">LIVE CATALOG</p>
          <h2>{t('models.title')}</h2>
        </div>
        <div className="panel-heading-actions">
          {compareCount > 0 && (
            <button type="button" className="btn btn-ghost btn-sm" onClick={() => compareCount >= 2 && setShowCompare(true)} disabled={compareCount < 2}>
              {t('models.compareAction', { count: compareCount })}
            </button>
          )}
          <span className="chip">{t('models.summary', { returned, total })}</span>
        </div>
      </div>
      {showFilters ? <FilterBar /> : null}
      {showCompare && compareCount >= 2 ? (
        <ComparePanel onClose={closeCompare} />
      ) : (
        <div className={`models-layout ${showDetails ? '' : 'details-collapsed'}`}>
          <ModelTable />
          {showDetails ? <DetailPanel /> : null}
        </div>
      )}
    </section>
  );
}

function Workspace() {
  const { t } = useI18n();
  const [navOpen, setNavOpen] = useState(true);
  const [showSystem, setShowSystem] = useState(true);
  const [showFilters, setShowFilters] = useState(true);
  const [showDetails, setShowDetails] = useState(true);

  return (
    <div className={`responsive-app ${navOpen ? 'nav-open' : 'nav-collapsed'}`}>
      <aside className="side-rail">
        <button className="rail-toggle" type="button" onClick={() => setNavOpen((value) => !value)} aria-label="Toggle navigation">{navOpen ? '‹' : '›'}</button>
        <div className="brand-mark">lf</div>
        {navOpen ? <><p className="rail-label">WORKSPACE</p><button className="rail-item active" type="button">◈ <span>Model explorer</span></button><button className="rail-item" type="button" onClick={() => setShowSystem((value) => !value)}>◫ <span>Hardware {showSystem ? 'visible' : 'hidden'}</span></button><button className="rail-item" type="button" onClick={() => setShowFilters((value) => !value)}>⌕ <span>Filters {showFilters ? 'visible' : 'hidden'}</span></button><button className="rail-item" type="button" onClick={() => setShowDetails((value) => !value)}>▣ <span>Inspector {showDetails ? 'visible' : 'hidden'}</span></button><div className="rail-spacer" /><p className="rail-hint">{t('header.copy')}</p></> : null}
      </aside>
      <main className="workspace">
        <div className="workspace-topbar"><div><span className="status-dot" /> LLMFIT CAPACITY LAB</div><div className="topbar-actions"><button className="topbar-button" type="button" onClick={() => setShowSystem((value) => !value)}>Hardware</button><button className="topbar-button" type="button" onClick={() => setShowFilters((value) => !value)}>Filters</button><button className="topbar-button" type="button" onClick={() => setShowDetails((value) => !value)}>Inspector</button></div></div>
        <Header />
        {showSystem ? <SystemPanel /> : null}
        <ModelsSection showFilters={showFilters} showDetails={showDetails} />
      </main>
    </div>
  );
}

export default function App() {
  return <I18nProvider><FilterProvider><ModelProvider><DataLoader /><Workspace /></ModelProvider></FilterProvider></I18nProvider>;
}
