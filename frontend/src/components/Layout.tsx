import { NavLink, Outlet } from 'react-router-dom'

// Introduced in Phase 5 alongside routing -- deliberately not built
// earlier for the single-page landing-only app (CLAUDE.md, "Deferred,
// not forgotten": "Nav bar -- comes naturally with Phase 5's routing").
// The model detail page gets a route but intentionally NO nav entry
// here (design doc: "no dedicated top-level menu entry... reached by
// clicking a row, not a separate nav item").
const NAV_LINK_CLASS = ({ isActive }: { isActive: boolean }) =>
  `text-sm font-medium ${isActive ? 'text-blue-600' : 'text-gray-500 hover:text-gray-700'}`

export function Layout() {
  return (
    <div className="min-h-screen">
      <header className="border-b border-gray-200">
        <div className="mx-auto flex max-w-6xl items-center gap-6 px-6 py-4">
          <NavLink to="/" className="text-lg font-semibold text-gray-900">
            NIMTracker
          </NavLink>
          <nav className="flex gap-4">
            <NavLink to="/" end className={NAV_LINK_CLASS}>
              Overview
            </NavLink>
            <NavLink to="/models" className={NAV_LINK_CLASS}>
              Models
            </NavLink>
          </nav>
        </div>
      </header>
      <Outlet />
    </div>
  )
}
