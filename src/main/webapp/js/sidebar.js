/* ================================================================
   Smart Care — Role-Based Sidebar (RBAC + Wireframe Aligned)
   Colors: sidebar #1a3a5c, active #2a5080, sub-sidebar #1a2e44
   Doctor sidebar: Dashboard, My Patients, Appointments, EMR, Ward, Profile
   Admin sidebar: All 8 modules
   CSG3101 Group 21 — Edith Crown University 2026
   ================================================================ */

const Sidebar = {

  allModules: [
    { id:'dashboard',     icon:'⊞',  text:'Dashboard',
      href:'../admin/dashboard.html',
      roles:['System Admin','Hospital Admin'],
      sub:[] },
    { id:'patients',      icon:'👤', text:'Patient Management',
      href:'../patients/list.html',
      roles:['System Admin','Hospital Admin','Doctor','Nurse','Receptionist'],
      sub:[
        { id:'patients-list',     icon:'👤', text:'Patients',         href:'../patients/list.html' },
        { id:'patients-register', icon:'➕', text:'Register Patient', href:'../patients/list.html#register' },
        { id:'patients-search',   icon:'🔍', text:'Search',           href:'../patients/list.html#search' },
        { id:'patients-reports',  icon:'📊', text:'Reports',          href:'../patients/list.html#reports' },
      ]
    },
    { id:'appointments',  icon:'📅', text:'Appointments',
      href:'../appointments/book.html',
      roles:['System Admin','Hospital Admin','Doctor','Nurse','Receptionist'],
      sub:[
        { id:'appointments-book',     icon:'📅', text:'Book Appointment',  href:'../appointments/book.html' },
        { id:'appointments-search',   icon:'🔍', text:'Search / Filter',   href:'../appointments/book.html#search' },
        { id:'appointments-schedule', icon:'📋', text:"Today's Schedule",  href:'../appointments/book.html#schedule' },
        { id:'appointments-reports',  icon:'📊', text:'Reports',           href:'../appointments/book.html#reports' },
      ]
    },
    { id:'emr',           icon:'📋', text:'EMR / Medical Records',
      href:'../emr/records.html',
      roles:['System Admin','Hospital Admin','Doctor','Nurse'],
      sub:[
        { id:'emr-records',   icon:'📋', text:'Patient Records', href:'../emr/records.html' },
        { id:'emr-new',       icon:'➕', text:'New Entry',        href:'../emr/records.html#new' },
        { id:'emr-documents', icon:'📎', text:'Documents',        href:'../emr/records.html#documents' },
        { id:'emr-reports',   icon:'📊', text:'Reports',          href:'../emr/records.html#reports' },
      ]
    },
    { id:'pharmacy',      icon:'💊', text:'Pharmacy',
      href:'../pharmacy/dashboard.html',
      roles:['System Admin','Hospital Admin','Pharmacist'],
      sub:[
        { id:'pharmacy-inventory', icon:'💊', text:'Inventory',  href:'../pharmacy/dashboard.html' },
        { id:'pharmacy-dispense',  icon:'📋', text:'Dispense',   href:'../pharmacy/dashboard.html#dispense' },
        { id:'pharmacy-orders',    icon:'🛒', text:'Orders',      href:'../pharmacy/dashboard.html#orders' },
        { id:'pharmacy-reports',   icon:'📊', text:'Reports',     href:'../pharmacy/dashboard.html#reports' },
      ]
    },
    { id:'billing',       icon:'💰', text:'Billing',
      href:'../billing/dashboard.html',
      roles:['System Admin','Hospital Admin','Billing Clerk'],
      sub:[
        { id:'billing-invoices',  icon:'🧾', text:'Invoices',        href:'../billing/dashboard.html' },
        { id:'billing-payments',  icon:'💳', text:'Payments',         href:'../billing/dashboard.html#payments' },
        { id:'billing-insurance', icon:'📋', text:'Insurance Claims', href:'../billing/dashboard.html#insurance' },
        { id:'billing-reports',   icon:'📊', text:'Reports',          href:'../billing/dashboard.html#reports' },
      ]
    },
    { id:'beds',          icon:'🏥', text:'Bed & Ward',
      href:'../beds/ward.html',
      roles:['System Admin','Hospital Admin','Doctor','Nurse'],
      sub:[
        { id:'beds-overview',  icon:'🛏', text:'Ward Overview', href:'../beds/ward.html' },
        { id:'beds-admit',     icon:'➕', text:'Admit Patient', href:'../beds/ward.html#admit' },
        { id:'beds-transfers', icon:'🔄', text:'Transfers',     href:'../beds/ward.html#transfers' },
        { id:'beds-discharge', icon:'📤', text:'Discharge',     href:'../beds/ward.html#discharge' },
        { id:'beds-reports',   icon:'📊', text:'Reports',       href:'../beds/ward.html#reports' },
      ]
    },
    { id:'staff',         icon:'👥', text:'Staff & HR',
      href:'../staff/employees.html',
      roles:['System Admin','Hospital Admin','HR Manager'],
      sub:[
        { id:'staff-profiles',   icon:'👥', text:'Staff Profiles',      href:'../staff/employees.html' },
        { id:'staff-create',     icon:'➕', text:'Create Staff Profile', href:'../staff/employees.html#create' },
        { id:'staff-scheduling', icon:'🗓', text:'Scheduling',           href:'../staff/employees.html#scheduling' },
        { id:'staff-attendance', icon:'⏱', text:'Attendance',            href:'../staff/employees.html#attendance' },
        { id:'staff-leave',      icon:'📋', text:'Leave Requests',       href:'../staff/employees.html#leave' },
        { id:'staff-reports',    icon:'📊', text:'Reports',              href:'../staff/employees.html#reports' },
      ]
    },
    { id:'security',      icon:'🔒', text:'Security & Audit',
      href:'../security/dashboard.html',
      roles:['System Admin','Hospital Admin'],
      sub:[
        { id:'security-audit',   icon:'📋', text:'Audit Log',       href:'../security/dashboard.html' },
        { id:'security-users',   icon:'👤', text:'User Management', href:'../security/dashboard.html#users' },
        { id:'security-rbac',    icon:'🔐', text:'RBAC Roles',      href:'../security/dashboard.html#rbac' },
        { id:'security-anomaly', icon:'🚨', text:'Anomaly Alerts',  href:'../security/dashboard.html#anomaly' },
        { id:'security-hipaa',   icon:'📑', text:'HIPAA Report',    href:'../security/dashboard.html#hipaa' },
      ]
    },
  ],

  /* Doctor-specific sidebar modules (wireframe Page 2 exact) */
  doctorModules: [
    { id:'doc-dashboard', icon:'🏠', text:'Dashboard',     href:'../staff/doctor-dashboard.html#home',     panelId:'home' },
    { id:'doc-patients',  icon:'👤', text:'My Patients',   href:'../staff/doctor-dashboard.html#patients', panelId:'patients' },
    { id:'doc-appts',     icon:'📅', text:'Appointments',  href:'../staff/doctor-dashboard.html#appts',    panelId:'appts' },
    { id:'doc-emr',       icon:'📋', text:'EMR',           href:'../staff/doctor-dashboard.html#emr',      panelId:'emr' },
    { id:'doc-ward',      icon:'🛏', text:'Ward',          href:'../staff/doctor-dashboard.html#ward',     panelId:'ward' },
    { id:'doc-profile',   icon:'👤', text:'Profile',       href:'../staff/doctor-dashboard.html#profile',  panelId:'profile' },
  ],

  normalizeRole(role) {
    const raw = String(role || '').trim();
    if (!raw) return 'System Admin';
    const aliases = {
      'Admin': 'System Admin',
      'Billing Admin': 'Billing Clerk',
      'HospitalAdministrator': 'Hospital Admin'
    };
    return aliases[raw] || raw;
  },

  getModulesForRole(role) {
    const normalizedRole = this.normalizeRole(role);
    if (normalizedRole === 'Patient') return [];
    const modules = this.allModules.filter(m => m.roles.includes(normalizedRole));
    // Defensive fallback: never render an empty sidebar for authenticated staff.
    if (modules.length) return modules;
    return this.allModules.filter(m => m.roles.includes('System Admin'));
  },

  render(activeModuleId, activeSubId, mainId='sidebar', subId='sub-sidebar') {
    const user = Auth.getUser();
    const role = this.normalizeRole(user.role || user.roleName);

    // Doctor portal uses its own sidebar
    if (role === 'Doctor') {
      this._renderDoctorSidebar(activeModuleId, mainId);
      const subEl = document.getElementById(subId);
      if (subEl) { subEl.classList.add('hidden'); subEl.innerHTML = ''; }
      return;
    }

    const modules = this.getModulesForRole(role);
    this._renderMain(activeModuleId, mainId, modules, role);
    this._renderSub(activeModuleId, activeSubId, subId, modules);
    this._updateTopbar(activeModuleId, activeSubId, modules);
  },

  /* ── Doctor Sidebar (wireframe Page 2 exact layout) ─────── */
  _renderDoctorSidebar(activeId, containerId) {
    const el = document.getElementById(containerId);
    if (!el) return;

    const user = Auth.getUser();
    const initials = (user.username || 'DR').substring(0,2).toUpperCase();

    let html = `
      <div class="sidebar-logo" style="padding:14px 14px 10px;border-bottom:1px solid rgba(255,255,255,0.1);display:flex;align-items:center;gap:10px">
        <img src="/smart-care/images/logo.png" alt="SmartCare" style="width:30px;height:30px;object-fit:contain;flex-shrink:0;background:#0f2540;border-radius:6px;padding:3px">
        <div class="logo-text">
          <h1 style="font-size:16px;font-weight:800;letter-spacing:-0.3px;margin:0"><span style="color:#1D9E75">Smart</span><span style="color:#F5A623">Care</span></h1>
          <p style="font-size:9px;color:rgba(255,255,255,0.45);margin:0">Doctor Portal</p>
        </div>
      </div>
      <div style="padding:10px 14px 6px;border-bottom:1px solid rgba(255,255,255,0.08);margin-bottom:4px">
        <div style="font-size:9px;color:rgba(255,255,255,0.4);text-transform:uppercase;letter-spacing:0.8px">Role</div>
        <div style="font-size:12px;font-weight:700;color:rgba(255,255,255,0.9);margin-top:2px">👨‍⚕️ Doctor</div>
        <div style="font-size:10px;color:rgba(255,255,255,0.5);margin-top:1px">${user.username || ''}</div>
      </div>
      <div class="nav-section" style="flex:1">`;

    this.doctorModules.forEach(mod => {
      const isActive = activeId === mod.id || activeId === mod.panelId;
      html += `<a class="nav-item${isActive ? ' active' : ''}" href="#"
        onclick="if(window.showPanel){showPanel('${mod.panelId}');return false;}">
        <span class="nav-icon">${mod.icon}</span>${mod.text}
      </a>`;
    });

    html += `</div>
      <div style="padding:10px 14px;border-top:1px solid rgba(255,255,255,0.08)">
        <button class="nav-item" style="width:100%;background:none;border:none;cursor:pointer;color:rgba(255,255,255,0.55);font-size:13px;text-align:left" onclick="Auth.logout()">
          <span class="nav-icon">🚪</span>Logout
        </button>
      </div>`;
    el.innerHTML = html;
  },

  /* ── Main sidebar (admin/staff roles) ────────────────────── */
  _renderMain(activeModuleId, containerId, modules, role) {
    const el = document.getElementById(containerId);
    if (!el) return;

    const roleIcons = {
      'System Admin':'🛡','Hospital Admin':'🏥','Nurse':'👩‍⚕️',
      'Pharmacist':'💊','Billing Clerk':'💰','HR Manager':'👥','Receptionist':'📋'
    };

    let html = `
      <div class="sidebar-logo" style="padding:14px 14px 10px;border-bottom:1px solid rgba(255,255,255,0.1);display:flex;align-items:center;gap:10px">
        <img src="/smart-care/images/logo.png" alt="SmartCare" style="width:30px;height:30px;object-fit:contain;flex-shrink:0;background:#0f2540;border-radius:6px;padding:3px">
        <div class="logo-text">
          <h1 style="font-size:16px;font-weight:800;letter-spacing:-0.3px;margin:0"><span style="color:#1D9E75">Smart</span><span style="color:#F5A623">Care</span></h1>
          <p style="font-size:9px;color:rgba(255,255,255,0.45);margin:0">Hospital ERP</p>
        </div>
      </div>
      <div style="padding:8px 14px 6px;border-bottom:1px solid rgba(255,255,255,0.08);margin-bottom:4px">
        <div style="font-size:9px;color:rgba(255,255,255,0.4);text-transform:uppercase;letter-spacing:0.8px">Role</div>
        <div style="font-size:12px;font-weight:700;color:rgba(255,255,255,0.9);margin-top:2px">${roleIcons[role]||'👤'} ${role}</div>
      </div>
      <div class="nav-section" style="flex:1">`;

    // Dashboard only for admin roles
    if (role === 'System Admin' || role === 'Hospital Admin') {
      const isActive = activeModuleId === 'dashboard';
      html += `<a class="nav-item${isActive ? ' active':''}" href="../admin/dashboard.html">
        <span class="nav-icon">⊞</span>Dashboard
      </a>`;
    }

    modules.filter(m => m.id !== 'dashboard').forEach(mod => {
      const isActive = mod.id === activeModuleId;
      const href = mod.sub.length ? mod.sub[0].href : mod.href;
      html += `<a class="nav-item${isActive ? ' active':''}" href="${href}">
        <span class="nav-icon">${mod.icon}</span>${mod.text}
      </a>`;
    });

    html += `</div>
      <div style="padding:10px 14px;border-top:1px solid rgba(255,255,255,0.08)">
        <button class="nav-item" style="width:100%;background:none;border:none;cursor:pointer;color:rgba(255,255,255,0.55);font-size:13px;text-align:left" onclick="Auth.logout()">
          <span class="nav-icon">🚪</span>Logout
        </button>
      </div>`;
    el.innerHTML = html;
  },

  /* ── Sub sidebar ─────────────────────────────────────────── */
  _renderSub(activeModuleId, activeSubId, containerId, modules) {
    const el = document.getElementById(containerId);
    if (!el) return;
    const mod = modules.find(m => m.id === activeModuleId);
    if (!mod || !mod.sub || !mod.sub.length) { el.classList.add('hidden'); el.innerHTML=''; return; }
    el.classList.remove('hidden');
    const effectiveSub = activeSubId || mod.sub[0].id;
    let html = `
      <div class="sub-sidebar-header">
        <div class="sub-sidebar-module-label">Module</div>
        <div class="sub-sidebar-module-name">${mod.icon} ${mod.text}</div>
      </div>
      <div class="nav-section" style="padding:4px 0;flex:1">`;
    mod.sub.forEach(sub => {
      const isActive = sub.id === effectiveSub;
      html += `<a class="nav-sub-item${isActive?' active':''}" href="${sub.href}">
        <span class="nav-sub-icon">${sub.icon}</span>${sub.text}
      </a>`;
    });
    html += `</div>`;
    el.innerHTML = html;
  },

  _updateTopbar(activeModuleId, activeSubId, modules) {
    const mod = modules.find(m => m.id === activeModuleId);
    const breadEl = document.getElementById('topbar-breadcrumb');
    if (breadEl && mod) breadEl.textContent = `SmartCare | ${mod.text}`;
  }
};
