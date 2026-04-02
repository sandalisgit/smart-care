/* ================================================================
   Smart Care — Two-Column Sidebar
   Matches screenshot: main nav column + sub-page column side by side
   Extracted exactly from final__1_.xml wireframe (2884 cells, Page 3)

   Usage: Sidebar.render('patients', 'patients-list')
          arg1 = active module ID
          arg2 = active sub-page ID
   ================================================================ */

const Sidebar = {

  modules: [
    { id:'dashboard', icon:'⊞', text:'Dashboard',
      href:'../admin/dashboard.html', sub:[] },
    {
      id:'patients', icon:'👤', text:'Patient Management',
      href:'../patients/list.html',
      sub:[
        { id:'patients-list',     icon:'👤', text:'Patients',         href:'../patients/list.html' },
        { id:'patients-register', icon:'➕', text:'Register Patient', href:'../patients/list.html#register' },
        { id:'patients-search',   icon:'🔍', text:'Search',           href:'../patients/list.html#search' },
        { id:'patients-reports',  icon:'📊', text:'Reports',          href:'../patients/list.html#reports' },
      ]
    },
    {
      id:'appointments', icon:'📅', text:'Appointments',
      href:'../appointments/book.html',
      sub:[
        { id:'appointments-book',     icon:'📅', text:'Book Appointment',  href:'../appointments/book.html' },
        { id:'appointments-search',   icon:'🔍', text:'Search / Filter',   href:'../appointments/book.html#search' },
        { id:'appointments-schedule', icon:'📋', text:"Today's Schedule",  href:'../appointments/book.html#schedule' },
        { id:'appointments-reports',  icon:'📊', text:'Reports',           href:'../appointments/book.html#reports' },
      ]
    },
    {
      id:'emr', icon:'📋', text:'EMR / Medical Records',
      href:'../emr/records.html',
      sub:[
        { id:'emr-records',   icon:'📋', text:'Patient Records', href:'../emr/records.html' },
        { id:'emr-new',       icon:'➕', text:'New Entry',        href:'../emr/records.html#new' },
        { id:'emr-documents', icon:'📎', text:'Documents',        href:'../emr/records.html#documents' },
        { id:'emr-reports',   icon:'📊', text:'Reports',          href:'../emr/records.html#reports' },
      ]
    },
    {
      id:'pharmacy', icon:'💊', text:'Pharmacy',
      href:'../pharmacy/dashboard.html',
      sub:[
        { id:'pharmacy-inventory', icon:'💊', text:'Inventory',  href:'../pharmacy/dashboard.html' },
        { id:'pharmacy-dispense',  icon:'📋', text:'Dispense',   href:'../pharmacy/dashboard.html#dispense' },
        { id:'pharmacy-orders',    icon:'🛒', text:'Orders',      href:'../pharmacy/dashboard.html#orders' },
        { id:'pharmacy-reports',   icon:'📊', text:'Reports',     href:'../pharmacy/dashboard.html#reports' },
      ]
    },
    {
      id:'billing', icon:'💰', text:'Billing',
      href:'../billing/dashboard.html',
      sub:[
        { id:'billing-invoices',  icon:'🧾', text:'Invoices',        href:'../billing/dashboard.html' },
        { id:'billing-payments',  icon:'💳', text:'Payments',         href:'../billing/dashboard.html#payments' },
        { id:'billing-insurance', icon:'📋', text:'Insurance Claims', href:'../billing/dashboard.html#insurance' },
        { id:'billing-reports',   icon:'📊', text:'Reports',          href:'../billing/dashboard.html#reports' },
      ]
    },
    {
      id:'beds', icon:'🏥', text:'Bed & Ward',
      href:'../beds/ward.html',
      sub:[
        { id:'beds-overview',  icon:'🛏', text:'Ward Overview', href:'../beds/ward.html' },
        { id:'beds-admit',     icon:'➕', text:'Admit Patient', href:'../beds/ward.html#admit' },
        { id:'beds-transfers', icon:'🔄', text:'Transfers',     href:'../beds/ward.html#transfers' },
        { id:'beds-discharge', icon:'📤', text:'Discharge',     href:'../beds/ward.html#discharge' },
        { id:'beds-reports',   icon:'📊', text:'Reports',       href:'../beds/ward.html#reports' },
      ]
    },
    {
      id:'staff', icon:'👥', text:'Staff & HR',
      href:'../staff/employees.html',
      sub:[
        { id:'staff-profiles',   icon:'👥', text:'Staff Profiles',      href:'../staff/employees.html' },
        { id:'staff-create',     icon:'➕', text:'Create Staff Profile', href:'../staff/employees.html#create' },
        { id:'staff-scheduling', icon:'🗓', text:'Scheduling',           href:'../staff/employees.html#scheduling' },
        { id:'staff-attendance', icon:'⏱', text:'Attendance',            href:'../staff/employees.html#attendance' },
        { id:'staff-leave',      icon:'📋', text:'Leave Requests',       href:'../staff/employees.html#leave' },
        { id:'staff-reports',    icon:'📊', text:'Reports',              href:'../staff/employees.html#reports' },
      ]
    },
    {
      id:'security', icon:'🔒', text:'Security & Audit',
      href:'../security/dashboard.html',
      sub:[
        { id:'security-audit',   icon:'📋', text:'Audit Log',       href:'../security/dashboard.html' },
        { id:'security-users',   icon:'👤', text:'User Management', href:'../security/dashboard.html#users' },
        { id:'security-rbac',    icon:'🔐', text:'RBAC Roles',      href:'../security/dashboard.html#rbac' },
        { id:'security-anomaly', icon:'🚨', text:'Anomaly Alerts',  href:'../security/dashboard.html#anomaly' },
        { id:'security-hipaa',   icon:'📑', text:'HIPAA Report',    href:'../security/dashboard.html#hipaa' },
      ]
    },
  ],

  /**
   * Render both sidebar columns.
   * @param {string} activeModuleId  — 'patients', 'appointments', etc.
   * @param {string} activeSubId     — 'patients-list', 'patients-register', etc.
   * @param {string} mainId          — id of main <nav> element (default 'sidebar')
   * @param {string} subId           — id of sub <nav> element (default 'sub-sidebar')
   */
  render(activeModuleId, activeSubId, mainId = 'sidebar', subId = 'sub-sidebar') {
    this._renderMain(activeModuleId, mainId);
    this._renderSub(activeModuleId, activeSubId, subId);
    this._updateTopbar(activeModuleId, activeSubId);
  },

  /* ── Main sidebar (left column) ─────────────────────────────── */
  _renderMain(activeModuleId, containerId) {
    const el = document.getElementById(containerId);
    if (!el) return;

    let html = `
      <div class="sidebar-logo">
        <div class="logo-icon">🏥</div>
        <div class="logo-text">
          <h1><span class="t">Smart</span><span class="o">Care</span></h1>
          <p>Hospital ERP</p>
        </div>
      </div>
      <div class="nav-section">`;

    this.modules.forEach(mod => {
      const isActive = mod.id === activeModuleId;
      const href = mod.sub.length ? mod.sub[0].href : mod.href;
      html += `
        <a class="nav-item${isActive ? ' active' : ''}" href="${href}">
          <span class="nav-icon">${mod.icon}</span>${mod.text}
        </a>`;
    });

    html += `</div>
      <div style="margin-top:auto;padding:12px 0;border-top:1px solid rgba(255,255,255,0.08)">
        <button class="nav-item"
          style="width:100%;background:none;border:none;cursor:pointer;
                 color:rgba(255,255,255,0.55);font-size:13px;text-align:left"
          onclick="Auth.logout()">
          <span class="nav-icon">🚪</span>Logout
        </button>
      </div>`;

    el.innerHTML = html;
  },

  /* ── Sub sidebar (right column) ─────────────────────────────── */
  _renderSub(activeModuleId, activeSubId, containerId) {
    const el = document.getElementById(containerId);
    if (!el) return;

    const mod = this.modules.find(m => m.id === activeModuleId);

    /* Dashboard has no sub-column — hide it */
    if (!mod || !mod.sub.length) {
      el.classList.add('hidden');
      el.innerHTML = '';
      return;
    }

    el.classList.remove('hidden');

    /* Default to first sub-item if none specified */
    const effectiveSub = activeSubId || mod.sub[0].id;

    let html = `
      <div class="sub-sidebar-header">
        <div class="sub-sidebar-module-label">Module</div>
        <div class="sub-sidebar-module-name">${mod.icon} ${mod.text}</div>
      </div>
      <div class="nav-section" style="padding:4px 0;flex:1">`;

    mod.sub.forEach(sub => {
      const isActive = sub.id === effectiveSub;
      html += `
        <a class="nav-sub-item${isActive ? ' active' : ''}" href="${sub.href}">
          <span class="nav-sub-icon">${sub.icon}</span>${sub.text}
        </a>`;
    });

    html += `</div>`;
    el.innerHTML = html;
  },

  /* ── Update topbar breadcrumb if present ─────────────────────── */
  _updateTopbar(activeModuleId, activeSubId) {
    const mod = this.modules.find(m => m.id === activeModuleId);
    const sub = mod && mod.sub.find(s => s.id === activeSubId);

    const breadEl = document.getElementById('topbar-breadcrumb');
    if (breadEl && mod) {
      breadEl.textContent = `SmartCare | ${mod.text}`;
    }

    const titleEl = document.querySelector('.topbar-title');
    if (titleEl && mod) {
      if (sub && sub.text !== mod.text && sub.text !== 'Patients' &&
          sub.text !== 'Invoices' && sub.text !== 'Inventory' &&
          sub.text !== 'Audit Log' && sub.text !== 'Ward Overview' &&
          sub.text !== 'Patient Records' && sub.text !== 'Staff Profiles' &&
          sub.text !== 'Book Appointment') {
        titleEl.textContent = sub.text;
      }
    }
  }
};
