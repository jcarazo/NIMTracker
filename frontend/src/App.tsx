import { HashRouter, Route, Routes } from 'react-router-dom'
import { Layout } from './components/Layout'
import { ExecutionsPage } from './pages/ExecutionsPage'
import { LandingPage } from './pages/LandingPage'
import { ModelDetailPage } from './pages/ModelDetailPage'
import { ModelsPage } from './pages/ModelsPage'

// HashRouter, not BrowserRouter -- deliberate Phase 5 choice, not an
// oversight. Deployment is GitHub Pages (CLAUDE.md), which has no SPA
// fallback routing set up yet (that's still Phase 7). BrowserRouter
// would 404 on a direct link or refresh to e.g. /models/foo since GH
// Pages has no real file at that path; HashRouter (/#/models/foo) never
// hits the server for a route change at all, sidestepping the problem
// with zero deploy config. See CLAUDE.md, "Architecture", for the full
// note -- revisiting this is an explicit Phase 7 decision (once the
// 404.html SPA-fallback trick exists), not something to "fix" here by
// swapping back to BrowserRouter without re-reading why.
//
// /models/* is a splat route, not /models/:slug -- model.slug contains
// a literal '/' (e.g. 'moonshotai/kimi-k3'), which a single :slug param
// wouldn't match correctly. The splat captures the full trailing path
// verbatim, so no encoding/decoding is needed anywhere.
function App() {
  return (
    <HashRouter>
      <Routes>
        <Route element={<Layout />}>
          <Route index element={<LandingPage />} />
          <Route path="models" element={<ModelsPage />} />
          <Route path="models/*" element={<ModelDetailPage />} />
          <Route path="executions" element={<ExecutionsPage />} />
        </Route>
      </Routes>
    </HashRouter>
  )
}

export default App
