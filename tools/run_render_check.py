"""Run Godot GPU checks on a separate Windows desktop, without switching to it.

Python stdlib only. The GPU window never belongs to the user's input desktop.
Usage: python tools/run_render_check.py --log <absolute-log-path>
"""
import argparse
import ctypes as c
from ctypes import wintypes as w
from pathlib import Path
import subprocess


class StartupInfo(c.Structure):
    _fields_ = [('cb',w.DWORD),('reserved',w.LPWSTR),('desktop',w.LPWSTR),('title',w.LPWSTR),
                ('x',w.DWORD),('y',w.DWORD),('width',w.DWORD),('height',w.DWORD),
                ('chars_x',w.DWORD),('chars_y',w.DWORD),('fill',w.DWORD),('flags',w.DWORD),
                ('show',w.WORD),('reserved_count',w.WORD),('reserved_bytes',c.c_void_p),
                ('stdin',w.HANDLE),('stdout',w.HANDLE),('stderr',w.HANDLE)]


class ProcessInfo(c.Structure):
    _fields_ = [('process',w.HANDLE),('thread',w.HANDLE),('pid',w.DWORD),('tid',w.DWORD)]


def run(log, script='tools/render_actions_check.gd', timeout=60, project=None, extra_args=()):
    user = c.WinDLL('user32',use_last_error=True)
    kernel = c.WinDLL('kernel32',use_last_error=True)
    user.CreateDesktopW.argtypes = [w.LPCWSTR,w.LPCWSTR,c.c_void_p,w.DWORD,w.DWORD,c.c_void_p]
    user.CreateDesktopW.restype = w.HANDLE
    user.OpenInputDesktop.argtypes = [w.DWORD,w.BOOL,w.DWORD]
    user.OpenInputDesktop.restype = w.HANDLE
    user.GetUserObjectInformationW.argtypes = [w.HANDLE,c.c_int,c.c_void_p,w.DWORD,c.c_void_p]
    user.CloseDesktop.argtypes = [w.HANDLE]
    kernel.CreateProcessW.argtypes = [w.LPCWSTR,w.LPWSTR,c.c_void_p,c.c_void_p,w.BOOL,w.DWORD,c.c_void_p,w.LPCWSTR,c.POINTER(StartupInfo),c.POINTER(ProcessInfo)]
    kernel.WaitForSingleObject.argtypes = [w.HANDLE,w.DWORD]
    kernel.GetExitCodeProcess.argtypes = [w.HANDLE,c.POINTER(w.DWORD)]
    kernel.TerminateProcess.argtypes = [w.HANDLE,w.UINT]
    kernel.CloseHandle.argtypes = [w.HANDLE]

    def input_desktop():
        handle = user.OpenInputDesktop(0,False,0x0001)
        if not handle:
            raise c.WinError(c.get_last_error())
        try:
            name = c.create_unicode_buffer(256)
            if not user.GetUserObjectInformationW(handle,2,name,c.sizeof(name),None):
                raise c.WinError(c.get_last_error())
            return name.value
        finally:
            user.CloseDesktop(handle)

    source_root = Path(__file__).resolve().parents[1]
    root = project.resolve() if project else source_root
    # Own the engine process itself, so a timeout cannot orphan a console wrapper's child.
    godot = source_root.parent/'Tools/Godot/Godot_v4.7.2-stable_win64.exe'
    before = input_desktop()
    name = 'CodexRenderCheck'
    desktop = user.CreateDesktopW(name,None,None,0,0x000F01FF,None)
    if not desktop:
        raise c.WinError(c.get_last_error())
    info = ProcessInfo()
    try:
        startup = StartupInfo()
        startup.cb = c.sizeof(startup)
        startup.desktop = 'WinSta0\\'+name
        startup.flags = 1 # STARTF_USESHOWWINDOW
        startup.show = 0 # SW_HIDE
        arguments = [str(godot),'--path',str(root),'--resolution','64x64','--log-file',str(log)]
        if script:
            arguments += ['--script',script]
        arguments += list(extra_args)
        command = c.create_unicode_buffer(subprocess.list2cmdline(arguments))
        if not kernel.CreateProcessW(str(godot),command,None,None,False,0x08000000,None,str(root),c.byref(startup),c.byref(info)):
            raise c.WinError(c.get_last_error())
        if kernel.WaitForSingleObject(info.process,timeout*1000) != 0:
            kernel.TerminateProcess(info.process,1)
            raise TimeoutError(f'Isolated GPU check exceeded {timeout} seconds')
        status = w.DWORD()
        if not kernel.GetExitCodeProcess(info.process,c.byref(status)):
            raise c.WinError(c.get_last_error())
        assert input_desktop()==before,'Input desktop changed during the check'
        print(f'OFFSCREEN_CHECK: exit={status.value}; input desktop remained {before}; no desktop switch performed')
        return status.value
    finally:
        if info.thread:
            kernel.CloseHandle(info.thread)
        if info.process:
            kernel.CloseHandle(info.process)
        user.CloseDesktop(desktop)


if __name__=='__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--log',type=Path,required=True)
    parser.add_argument('--script',default='tools/render_actions_check.gd')
    parser.add_argument('--timeout',type=int,default=60)
    parser.add_argument('--project',type=Path)
    args = parser.parse_args()
    raise SystemExit(run(args.log.resolve(),args.script,args.timeout,args.project))
