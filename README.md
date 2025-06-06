# Personal Homelab Utilities Repository

A comprehensive collection of utilities, scripts, and configurations for managing and optimizing my personal homelab infrastructure. This repository serves as a centralized location for reusable tools and documentation for various homelab components.

## 🎯 Repository Goals

This repository aims to:
- **Centralize homelab utilities** in one accessible location
- **Provide production-ready scripts** with proper error handling and logging
- **Enable easy deployment** through automated installers
- **Document configurations** for reproducible setups
- **Share knowledge** with the homelab community
- **Maintain version control** for critical infrastructure scripts

## 🚀 Available Utilities

### 🌡️ Fan Control Systems

#### HP iLO4 Fan Control (`proxmox/ilo4/`)
**Comprehensive fan control system for HP ProLiant servers with iLO4**

- ✅ **Configurable temperature thresholds** with dynamic TEMP_STEPS array
- ✅ **Automatic temperature-based control** with emergency protection
- ✅ **Manual control interface** with interactive and CLI modes
- ✅ **Advanced threshold management** (add/remove temperature steps)
- ✅ **Intelligent installer** that loads existing configurations as defaults
- ✅ **Systemd service integration** with comprehensive logging
- ✅ **Production-ready** with robust error handling and failsafe modes

**Key Features:**
- Dynamic temperature thresholds: 90°C=255, 80°C=200, 70°C=150, 60°C=100, 50°C=75
- CLI management interface for threshold configuration
- Emergency protection and automatic failback
- Professional documentation with troubleshooting guide

**Installation:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/install.sh)"
```

#### Supermicro IPMI Fan Control (`proxmox/ipmi/`)
**Advanced IPMI-based fan control for Supermicro X10-X13 series motherboards**

- ✅ **Dynamic temperature control** for CPU and HDD monitoring
- ✅ **IPMI zone management** with separate CPU and peripheral zones
- ✅ **Multiple temperature sources** (thermal zones, sensors, IPMI, HDD)
- ✅ **Flexible fan curves** with configurable temperature-to-speed mapping
- ✅ **Auto-detection** of available fans via IPMI sensors
- ✅ **Sensor threshold management** to prevent IPMI takeover
- ✅ **Safety features** with automatic reset on shutdown

**Key Features:**
- Supports Supermicro X10, X11, X12, X13 series motherboards
- Daemon mode with systemd service integration
- Manual control utilities and threshold management
- HDD temperature monitoring with smartctl integration
- Comprehensive logging and error handling

**Installation:**
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ipmi/install.sh)"
```

## 📁 Repository Structure

```
homelab/
├── README.md                           # This file - repository overview
├── LICENSE                            # Repository license
└── proxmox/                           # Proxmox VE related utilities
    ├── ilo4/                          # HP iLO4 Fan Control System
    │   ├── install.sh                 # One-line installer with config loading
    │   ├── ilo4-fan-control.sh        # Main temperature control service
    │   ├── ilo4-fan-control-manual.sh # Manual control interface
    │   ├── set-thresholds.sh          # Threshold management CLI
    │   ├── ilo4-fan-control.conf      # Configuration template
    │   ├── ilo4-fan-control.service   # Systemd service definition
    │   └── readme.md                  # Comprehensive documentation
    └── ipmi/                          # Supermicro IPMI Fan Control
        ├── install.sh                 # One-line installer
        ├── supermicro-fan-control.sh  # Main IPMI control daemon
        ├── fan-control-manual.sh      # Manual control utilities
        ├── set-thresholds.sh          # IPMI threshold management
        ├── supermicro-fan-control.service # Systemd service
        └── README.md                  # Detailed documentation
```

## 🛠️ Platform Support

### Operating Systems
- **Proxmox VE** (Primary target platform)
- **Debian** 10/11/12
- **Ubuntu** 18.04/20.04/22.04/24.04
- **Other systemd-based distributions**

### Hardware Support
- **HP ProLiant servers** with iLO4 (via SSH)
- **Supermicro motherboards** X10/X11/X12/X13 series (via IPMI)

## 🚀 Quick Start

### Choose Your System

#### For HP ProLiant Servers with iLO4:
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/install.sh)"
```

#### For Supermicro Motherboards:
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ipmi/install.sh)"
```

### What the Installers Do:
1. **Detect and load existing configurations** (if re-running)
2. **Install required dependencies** automatically
3. **Configure system-specific settings** with intelligent defaults
4. **Set up systemd services** for automatic startup
5. **Test configurations** before activation
6. **Provide comprehensive logging** and error handling

## 📚 Documentation

Each utility includes comprehensive documentation:

- **📖 Detailed README files** with installation and usage instructions
- **🔧 Configuration guides** with examples and best practices
- **🚨 Troubleshooting sections** for common issues
- **⚡ Quick reference commands** for daily operations
- **🛡️ Safety notes** and emergency procedures

## 🤝 Contributing

This is a personal homelab repository, but contributions are welcome:

1. **Bug reports** and feature requests via GitHub issues
2. **Pull requests** for improvements or new utilities
3. **Documentation improvements** and clarifications
4. **Testing** on different hardware configurations

## 📜 License

This repository is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## 🔗 Related Resources

- **Proxmox VE Documentation**: https://pve.proxmox.com/pve-docs/
- **HP iLO4 User Guide**: HP official documentation
- **Supermicro IPMI Reference**: Supermicro technical documentation
- **Homelab Community**: r/homelab, r/proxmox

---

**⚠️ Important Notes:**
- Always test configurations in a safe environment before production deployment
- Keep backups of working configurations before making changes
- Monitor system temperatures after initial setup
- Both systems include emergency protection features, but manual monitoring is recommended

**💡 Pro Tips:**
- Use the intelligent installers that load existing configs when re-running
- Enable debug logging temporarily when troubleshooting issues
- Check system logs regularly for any warnings or errors
- Both systems support manual override for emergency situations
