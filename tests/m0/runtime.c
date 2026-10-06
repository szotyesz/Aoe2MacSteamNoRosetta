/* Local Windows ARM64 acceptance probes. Each selected case is one process. */
#include <windows.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define CHECK(cond) do { if (!(cond)) { fprintf(stderr, "FAIL %s:%d: %s (error=%lu)\n", __FILE__, __LINE__, #cond, GetLastError()); return 1; } } while (0)
static LONG fault_filter(EXCEPTION_POINTERS *ep, void *expected)
{
    EXCEPTION_RECORD *rec = ep->ExceptionRecord;
    if (rec->ExceptionCode != EXCEPTION_ACCESS_VIOLATION || rec->NumberParameters < 2 ||
        rec->ExceptionInformation[0] != 1 || rec->ExceptionInformation[1] != (ULONG_PTR)expected ||
        !ep->ContextRecord->Pc || ep->ContextRecord->Pc != (ULONG_PTR)rec->ExceptionAddress)
        return EXCEPTION_CONTINUE_SEARCH;
    return EXCEPTION_EXECUTE_HANDLER;
}
static DWORD tls_slot;
static volatile LONG counter;
static void *thread_tebs[8];
static HANDLE start_event;
static DWORD WINAPI worker(void *arg)
{
    uintptr_t token = (uintptr_t)arg + 1;
    void *teb = NtCurrentTeb();
    if (!teb) return 3;
    thread_tebs[(uintptr_t)arg] = teb;
    if (!TlsSetValue(tls_slot, (void *)token)) return 1;
    if (WaitForSingleObject(start_event, 15000) != WAIT_OBJECT_0) return 4;
    for (unsigned i = 0; i < 10000; ++i) {
        if (TlsGetValue(tls_slot) != (void *)token || NtCurrentTeb() != teb) return 2;
        InterlockedIncrement(&counter);
        if (!(i % 1000)) Sleep(0);
    }
    return 0;
}
static int threads(void)
{
    HANDLE handles[8];
    tls_slot = TlsAlloc(); CHECK(tls_slot != TLS_OUT_OF_INDEXES);
    start_event = CreateEventW(NULL, TRUE, FALSE, NULL); CHECK(start_event);
    for (uintptr_t i=0; i<8; ++i) {
        handles[i] = CreateThread(NULL, 0, worker, (void *)i, 0, NULL);
        CHECK(handles[i]);
    }
    /* Keep every created thread alive until all eight TEBs are allocated. */
    CHECK(SetEvent(start_event));
    CHECK(WaitForMultipleObjects(8, handles, TRUE, 15000) == WAIT_OBJECT_0);
    for (unsigned i=0; i<8; ++i) {
        DWORD code = 99; CHECK(GetExitCodeThread(handles[i], &code)); CHECK(code == 0);
        CHECK(thread_tebs[i] && thread_tebs[i] != NtCurrentTeb());
        for (unsigned j=0; j<i; ++j) CHECK(thread_tebs[i] != thread_tebs[j]);
        CHECK(CloseHandle(handles[i]));
    }
    CHECK(counter == 80000); CHECK(TlsFree(tls_slot));
    CHECK(CloseHandle(start_event)); return 0;
}
static int memory(void)
{
    SYSTEM_INFO info; GetSystemInfo(&info); CHECK(info.dwPageSize == 4096);
    unsigned char *p = VirtualAlloc(NULL, 8192, MEM_RESERVE|MEM_COMMIT, PAGE_READWRITE);
    CHECK(p); p[0] = 42; p[4096] = 24;
    DWORD old; CHECK(VirtualProtect(p+4096, 4096, PAGE_READONLY, &old));
    CHECK(old == PAGE_READWRITE);
    MEMORY_BASIC_INFORMATION a, b;
    CHECK(VirtualQuery(p, &a, sizeof(a)) == sizeof(a));
    CHECK(VirtualQuery(p+4096, &b, sizeof(b)) == sizeof(b));
    CHECK(a.Protect == PAGE_READWRITE && b.Protect == PAGE_READONLY);
    p[0] = 43; CHECK(p[0] == 43 && p[4096] == 24);
    volatile LONG caught = 0;
    __try { *(volatile unsigned char *)(p+4096) = 99; }
    __except (fault_filter(GetExceptionInformation(), p+4096)) { caught = 1; }
    CHECK(caught == 1); CHECK(VirtualFree(p, 0, MEM_RELEASE)); return 0;
}
static int exceptions(void)
{
    volatile LONG app = 0, access = 0;
    __try { RaiseException(0xe0424242, 0, 0, NULL); }
    __except (GetExceptionCode() == 0xe0424242 ? EXCEPTION_EXECUTE_HANDLER : EXCEPTION_CONTINUE_SEARCH) { app = 1; }
    CHECK(app == 1);
    __try { *(volatile LONG *)(uintptr_t)0x1234 = 7; }
    __except (fault_filter(GetExceptionInformation(), (void *)(uintptr_t)0x1234)) { access = 1; }
    CHECK(access == 1); return 0;
}
static volatile LONG callbacks, callback_failures;
static void *callback_teb;
static BOOL CALLBACK locale(WCHAR *name, DWORD flags, LPARAM arg)
{
    (void)flags;
    if (!name || arg != 0x4242) return FALSE;
    InterlockedIncrement(&callbacks);
    /* GetProcessTimes uses Wine's native NtQueryInformationProcess service. */
    LARGE_INTEGER count;
    FILETIME create, exit, kernel, user, precise, coarse;
    GetSystemTimeAsFileTime(&coarse);
    GetSystemTimePreciseAsFileTime(&precise);
    uint64_t a = ((uint64_t)precise.dwHighDateTime << 32) | precise.dwLowDateTime;
    uint64_t b = ((uint64_t)coarse.dwHighDateTime << 32) | coarse.dwLowDateTime;
    BOOL okay = QueryPerformanceCounter(&count) && count.QuadPart > 0 &&
        GetProcessTimes(GetCurrentProcess(), &create, &exit, &kernel, &user) &&
        create.dwHighDateTime && a >= b && a-b < 10000000 && NtCurrentTeb() == callback_teb;
    if (!okay) InterlockedIncrement(&callback_failures);
    return okay;
}
static int callback_test(void)
{
    callback_teb = NtCurrentTeb(); CHECK(callback_teb);
    CHECK(EnumSystemLocalesEx(locale, LOCALE_ALL, 0x4242, NULL));
    CHECK(NtCurrentTeb() == callback_teb);
    CHECK(callbacks > 0 && callback_failures == 0); return 0;
}
static uint64_t shared_time(unsigned offset)
{
    /* KSYSTEM_TIME has LowPart, High1Time, High2Time. This layout is stable;
       avoid mixing a high half from one update with a low half from another. */
    volatile DWORD *p = (volatile DWORD *)(uintptr_t)(0x7ffe0000u + offset);
    DWORD low, high, again;
    do { high=p[1]; low=p[0]; again=p[2]; } while (high != again);
    return ((uint64_t)high << 32) | low;
}
static int shared(void)
{
    MEMORY_BASIC_INFORMATION info;
    CHECK(VirtualQuery((void *)(uintptr_t)0x7ffe0000, &info, sizeof(info)) == sizeof(info));
    CHECK(info.State == MEM_COMMIT);
    uint64_t first = shared_time(0x14); /* KUSER_SHARED_DATA.SystemTime */
    Sleep(50); uint64_t second = shared_time(0x14);
    FILETIME ft; GetSystemTimeAsFileTime(&ft);
    uint64_t api = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    CHECK(first > 0 && second > first);
    CHECK(api >= first && api - second < 10000000); /* within one second */
    return 0;
}
static int io_test(void)
{
    const WCHAR name[] = L"M0 Unicode \x00e1 file.tmp";
    const unsigned char payload[] = {0,1,2,0xff,0x42};
    unsigned char received[sizeof(payload)]; DWORD count;
    HANDLE h=CreateFileW(name, GENERIC_WRITE|GENERIC_READ, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    CHECK(h != INVALID_HANDLE_VALUE);
    CHECK(WriteFile(h, payload, sizeof(payload), &count, NULL) && count == sizeof(payload));
    CHECK(SetFilePointer(h, 0, NULL, FILE_BEGIN) == 0);
    CHECK(ReadFile(h, received, sizeof(received), &count, NULL) && count == sizeof(received));
    CHECK(!memcmp(payload, received, sizeof(payload))); CHECK(CloseHandle(h));
    CHECK(DeleteFileW(name)); return 0;
}
int main(int argc, char **argv)
{
    CHECK(argc == 2);
    int result;
    if (!strcmp(argv[1], "memory")) result=memory();
    else if (!strcmp(argv[1], "shared")) result=shared();
    else if (!strcmp(argv[1], "threads")) result=threads();
    else if (!strcmp(argv[1], "callback")) result=callback_test();
    else if (!strcmp(argv[1], "exceptions")) result=exceptions();
    else if (!strcmp(argv[1], "unhandled")) {
        *(volatile LONG *)(uintptr_t)0x1234 = 7;
        puts("FAIL unhandled fault returned"); return 1;
    }
    else if (!strcmp(argv[1], "io")) result=io_test();
    else return 2;
    if (!result) printf("M0 %s PASS\n", argv[1]);
    return result;
}
