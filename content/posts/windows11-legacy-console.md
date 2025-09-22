---
title: "Enabling the Legacy Console in Windows 11"
date: 2025-09-22T00:00:00Z
draft: false
tags: ["windows", "console", "terminal", "legacy"]
categories: ["tutorials"]
comments: true
---

When developing console applications, the Windows "Legacy Console" can be a handy tool. It behaves like the console present in Windows XP, allowing me to test how applications behave in this environment.

This makes it simple to test compatibility, without having to painstakingly copy what I'm running over to Windows XP, and ensure it is compiled correctly for that target. When I went to do this with conhost on Windows 11, I was met with an unpleasant surprise:

{{< figure src="/images/posts/windows11-legacy-console/legacy-console-surprise.png" alt="Screenshot of the grayed check box, with text 'The legacy console is not installed'" width="500" >}}

In unfortunately common Microsoft style, the documentation link it provided behind "Learn More" is totaly unhelpful, referencing an anchor that does not exist on the page, as of September 2025.

https://learn.microsoft.com/en-us/windows/console/legacymode#removal

This is clearly extremely confusing and bad UX, evident in this GitHub thread:
https://github.com/leecher1337/ntvdmx64/discussions/250

So, because Microsoft don't explain how to reenable it out of their own incompetence, I'll do their job for them.

The Legacy Console is still available, as a "[Feature on demand](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/features-on-demand-v2--capabilities)".

To install it, first open PowerShell as Adminstrator.

Then, run this command:
```powershell
Add-WindowsCapability -Online -Name Microsoft.Windows.Console.Legacy~~~~
```

If this worked successfully, you should see:

```
Path          :
Online        : True
RestartNeeded : False
```

Now, you can restart conhost, and the "Use Legacy Console" checkbox should no longer be gray.
