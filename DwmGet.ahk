#Requires AutoHotkey v2.0.0+
#Include "%A_ScriptDir%"
#Include ".\lib\Event.ahk"
#Include ".\lib\WaitForSingleObjectAsync.ahk"
;==============================================================
; DwmGet — DWM registry color accessor and change notifier
;
; GitHub: https://github.com/SevenKeyboard/dwm-get
; Author: SevenKeyboard Ltd. (2025)
; License: MIT License
;==============================================================

/*
Example Usage:
    msgbox(DwmGet.AccentColor)      ;  0xff00b9ff
    msgbox(DwmGet.NonexistentKey)   ;  ""
*/

class VersionManager_DwmGet
{
    static _ := this._init()
    static _init()    {
        global
        DWMGET_VERSION := "1.0.0"
        if (!this._verCheck(&EVENT_VERSION, "1.0.0"))
            throw error("Event version 1.x is required (minimum 1.0.0).")
        if (!this._verCheck(&WAITFORSINGLEOBJECTASYNC_VERSION, "1.0.0"))
            throw error("WaitForSingleObjectAsync version 1.x is required (minimum 1.0.0).")
        return true
    }
    static _verCheck(&actual, required)    {
        if !isSet(actual)
            return false
        actualMajor     := strSplit(actual, ".",, 2)[1]
        requiredMajor   := strSplit(required, ".",, 2)[1]
        if (actualMajor !== requiredMajor)
            return false
        return verCompare(actual, ">=" required)
    }
}
class DwmGet
{
    static _handles := {event:"", waitFunc:"", hKey:""}
        ,_objbmCloseRegistryKeysOnExit  := objBindMethod(this, "_closeRegistryKeysOnExit")
        ,_objbmChangedCallback          := objBindMethod(this, "_changedCallback")
        ,_userCallbacks := []
    
    static __get(valueName, *)    {
        /*
        AccentColor
        AlwaysHibernateThumbnails
        ColorizationAfterglow
        ColorizationAfterglowBalance
        ColorizationBlurBalance
        ColorizationColor
        ColorizationColorBalance
        ColorizationGlassAttribute
        ColorPrevalence
        Composition
        EnableAeroPeek
        EnableWindowColorization
        */
        return (data:=regRead("HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\DWM",valueName,"")
            ,(data==""?"":format("{:#x}",data)))
    }

    static onChanged(callback, addRemove := 1)    { ;  Handle callbacks as succinctly as possible.
        static hasRegCallback := false
            ,HKEY_CURRENT_USER          := 0x80000001
            ,KEY_NOTIFY                 := 0x0010
            ,ERROR_SUCCESS              := 0
            ,REG_NOTIFY_CHANGE_LAST_SET := 0x00000004
        prevIC := critical("On")
        if (!hasRegCallback)    {
            onExit(this._objbmCloseRegistryKeysOnExit)
            loop 1    {
                this._handles.event := Event()
                if (!this._handles.event.handle)    {
                    this._handles.event := ""
                    break
                }
                this._handles.waitFunc := WaitForSingleObjectAsync(this._handles.event.handle, this._objbmChangedCallback)
                lErrorCode := dllCall("Advapi32.dll\RegOpenKeyEx", "Ptr",HKEY_CURRENT_USER, "Str","SOFTWARE\Microsoft\Windows\DWM", "UInt",0, "UInt",KEY_NOTIFY, "Ptr*",&hKey := 0, "Int")
                if (lErrorCode !== ERROR_SUCCESS)    {
                    this._handles.waitFunc  := ""
                    this._handles.event     := ""
                    break
                }
                this._handles.hKey := hKey
                dllCall("Advapi32.dll\RegNotifyChangeKeyValue", "Ptr",this._handles.hKey, "Int",false, "UInt",REG_NOTIFY_CHANGE_LAST_SET, "Ptr",this._handles.event.handle, "Int",true, "Int")
                hasRegCallback := true
            }
            if (!hasRegCallback)    {
                critical(prevIC)
                return
            }
        }
        newList := []
        switch (addRemove)
        {
            case 1:
                for fn in this._userCallbacks    {
                    if (fn !== callback)
                        newList.push(fn)
                }
                newList.push(callback)
            case -1:
                newList.push(callback)
                for fn in this._userCallbacks    {
                    if (fn !== callback)
                        newList.push(fn)
                }
            case 0:
                for fn in this._userCallbacks    {
                    if (fn !== callback)
                        newList.push(fn)
                }
        }
        this._userCallbacks := newList
        if (!this._userCallbacks.Length)    {
            if (this._handles.hKey)
                dllCall("Advapi32.dll\RegCloseKey", "Ptr",this._handles.hKey, "Int")
            this._handles.waitFunc  := ""
            this._handles.event     := ""
            hasRegCallback := false
        }
        critical(prevIC)
    }
    static _changedCallback()    {
        static REG_NOTIFY_CHANGE_LAST_SET := 0x00000004
        if (this._userCallbacks.Length)    {
            for fn in this._userCallbacks
                if (fn.call())
                    break
        }
        dllCall("Advapi32.dll\RegNotifyChangeKeyValue", "Ptr",this._handles.hKey, "Int",false, "UInt",REG_NOTIFY_CHANGE_LAST_SET, "Ptr",this._handles.event.handle, "Int",true, "Int")
    }
    static _closeRegistryKeysOnExit(exitReason, exitCode)    {
        if (this._handles.hKey)
            dllCall("Advapi32.dll\RegCloseKey", "Ptr",this._handles.hKey, "Int")
        this._handles.waitFunc  := ""
        this._handles.event     := ""
    }
}