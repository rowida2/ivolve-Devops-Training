# Lab 20: Role-Based Authorization in Jenkins

## Lab Objective

- Create `user1` and `user2` in Jenkins.
- Assign the **admin** role to `user1` and a **read-only** role to `user2`.

---

## Lab

### 1. Install Jenkins

Add the official Jenkins repository, then install Jenkins using APT:

```bash
sudo mkdir -p /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null

sudo apt update
sudo apt install -y jenkins
```

### 2. Change the Jenkins Port (if 8080 is already in use)

Port 8080 was occupied on this machine, so Jenkins was moved to port 8081 using a systemd override:

```bash
sudo systemctl edit jenkins
```

Add the following content:

```ini
[Service]
Environment="JENKINS_PORT=8081"
```

Reload systemd:

```bash
sudo systemctl daemon-reload
```

### 3. Start and Enable Jenkins

Enable Jenkins to start automatically when the system boots, then start the service.

```bash
# Enable Jenkins on system startup
sudo systemctl enable jenkins

# Start Jenkins
sudo systemctl start jenkins

# Check service status
sudo systemctl status jenkins --no-pager
```

The service should be **active (running)**.

<img width="1702" height="802" alt="image" src="https://github.com/user-attachments/assets/0f5afc6c-7112-4611-b728-31cbe5be0afc" />


### 4. Unlock Jenkins

Retrieve the initial administrator password:

```bash
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Open Jenkins in your browser:

```text
http://localhost:8081
```

Enter the initial password, install the suggested plugins, and create the first administrator account.

### 5. Install Role-Based Authorization Strategy Plugin

From the Jenkins Dashboard:

1. Navigate to **Manage Jenkins → Plugins**.
2. Open **Available plugins**.
3. Search for **Role-based Authorization Strategy**.
4. Install the plugin and restart Jenkins.

This plugin allows administrators to define roles and assign specific permissions to Jenkins users.

### 6. Enable Role-Based Authorization

Navigate to:

**Manage Jenkins → Security → Authorization**

Select:

**Role-Based Strategy**, then click **Save**.

### 7. Create Roles

Navigate to:

**Manage Jenkins → Manage and Assign Roles → Manage Roles**

The existing `admin` role was used for administrative access.

Create a new role named `readonly` with the following permissions:

| Category | Permission |
|---|---|
| Overall | Read |
| Job | Read |

The `readonly` role allows users to view Jenkins and jobs without modifying them.

### 8. Create Users

Navigate to:

**Manage Jenkins → Users → Create User**

Create the following users:

| Username | Purpose |
|---|---|
| `user1` | Administrator |
| `user2` | Read-only user |

<img width="931" height="548" alt="users" src="https://github.com/user-attachments/assets/f2574d03-1006-4764-952c-4e39005f12a7" />


### 9. Assign Roles to Users

Navigate to:

**Manage Jenkins → Manage and Assign Roles → Assign Roles**

Assign the roles as follows:

| User | Assigned Role |
|---|---|
| `<main-admin-account>` | `admin` |
| `user1` | `admin` |
| `user2` | `readonly` |

The main administrator account retains administrative access.

<img width="937" height="1025" alt="assign-roles" src="https://github.com/user-attachments/assets/c5576784-a1c1-435d-81a9-43ce1269ea97" />


### 10. Test User Permissions

Log in with each account separately (use an Incognito/InPrivate window) to verify the assigned permissions.

#### User 1: Admin

Log in using `user1` and verify that the account can:

- Access the Jenkins Dashboard.
- Open **Manage Jenkins**.
- Access administrative settings.
- Create and configure Jenkins jobs.

<img width="1763" height="853" alt="user1-admin" src="https://github.com/user-attachments/assets/9b1817e0-0cd6-4256-9e7a-6521e6aac0cb" />

#### User 2: Read-only

Log in using `user2` and verify that the account can:

- Access the Jenkins Dashboard.
- View available jobs.
- View job details.

The account should **not** be able to:

- Create jobs.
- Configure existing jobs.
- Delete jobs.
- Access administrative settings.

<img width="1552" height="671" alt="user2-readonly" src="https://github.com/user-attachments/assets/4a5b3268-d4f2-43f9-9945-06ee653938d1" />




## Conclusion

In this lab, Jenkins was installed and configured with the Role-Based Authorization Strategy. Two users were created with different access levels: `user1` received administrative permissions, while `user2` received read-only permissions.

This demonstrates how Jenkins access can be controlled by assigning roles and permissions to individual users.