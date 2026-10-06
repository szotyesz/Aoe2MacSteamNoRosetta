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
static int execute_code(void *buffer)
{
    /* ARM64: mov w0, #42; ret. Rewrite and flush to test cache coherence. */
    const DWORD code42[] = {0x52800540, 0xd65f03c0};
    const DWORD code43[] = {0x52800560, 0xd65f03c0};
    memcpy(buffer, code42, sizeof(code42));
    CHECK(FlushInstructionCache(GetCurrentProcess(), buffer, sizeof(code42)));
    CHECK(((int (*)(void))buffer)() == 42);
    memcpy(buffer, code43, sizeof(code43));
    CHECK(FlushInstructionCache(GetCurrentProcess(), buffer, sizeof(code43)));
    CHECK(((int (*)(void))buffer)() == 43);
    return 0;
}
static int executable_memory(const char *kind)
{
    if (!strcmp(kind, "exec-heap")) {
        HANDLE heap = HeapCreate(HEAP_CREATE_ENABLE_EXECUTE, 0, 0); CHECK(heap);
        void *p = HeapAlloc(heap, 0, 16); CHECK(p);
        int result = execute_code(p);
        CHECK(HeapFree(heap, 0, p)); CHECK(HeapDestroy(heap));
        return result;
    }
    BOOL transition = !strcmp(kind, "exec-transition");
    DWORD protection = transition ? PAGE_READWRITE : PAGE_EXECUTE_READWRITE;
    /* Fixed unused address bounds the failure path: no address-space search. */
    void *p = VirtualAlloc((void *)(uintptr_t)0x60000000, 4096,
                          MEM_RESERVE|MEM_COMMIT, protection); CHECK(p);
    int result;
    if (transition) {
        DWORD old;
        const DWORD code[] = {0x52800540, 0xd65f03c0};
        memcpy(p, code, sizeof(code));
        CHECK(VirtualProtect(p, 4096, PAGE_EXECUTE_READ, &old)); CHECK(old == PAGE_READWRITE);
        CHECK(FlushInstructionCache(GetCurrentProcess(), p, sizeof(code)));
        CHECK(((int (*)(void))p)() == 42);
        CHECK(VirtualProtect(p, 4096, PAGE_READWRITE, &old)); CHECK(old == PAGE_EXECUTE_READ);
        ((DWORD *)p)[0] = 0x52800560;
        CHECK(VirtualProtect(p, 4096, PAGE_EXECUTE_READ, &old)); CHECK(old == PAGE_READWRITE);
        CHECK(FlushInstructionCache(GetCurrentProcess(), p, sizeof(code)));
        CHECK(((int (*)(void))p)() == 43);
        result = 0;
    } else result = execute_code(p);
    CHECK(VirtualFree(p, 0, MEM_RELEASE));
    return result;
}
/* EM-1 state cases. An executable-memory request may succeed or fail, but
 * Windows-visible state must match real accesses either way. Intentional
 * probes report faults instead of crashing so each case judges its oracle. */
static LONG any_access_violation(EXCEPTION_POINTERS *ep)
{
    return ep->ExceptionRecord->ExceptionCode == EXCEPTION_ACCESS_VIOLATION ?
        EXCEPTION_EXECUTE_HANDLER : EXCEPTION_CONTINUE_SEARCH;
}
static BOOL try_write(volatile unsigned char *p, unsigned char value)
{
    __try { *p = value; } __except (any_access_violation(GetExceptionInformation())) { return FALSE; }
    return *p == value;
}
static BOOL try_exec(void *p, int expected)
{
    int value = -1;
    FlushInstructionCache(GetCurrentProcess(), p, 8);
    __try { value = ((int (*)(void))p)(); }
    __except (any_access_violation(GetExceptionInformation())) { return FALSE; }
    return value == expected;
}
static void write_code(void *p, int value)
{
    const DWORD code[] = {0x52800000u | ((DWORD)value << 5), 0xd65f03c0u};  /* mov w0, #value; ret */
    memcpy(p, code, sizeof(code));
}
static BOOL query(void *p, DWORD state, DWORD protect)
{
    MEMORY_BASIC_INFORMATION info;
    if (VirtualQuery(p, &info, sizeof(info)) != sizeof(info)) return FALSE;
    printf("query %p state=0x%lx protect=0x%lx base=%p size=0x%zx\n", p,
           info.State, info.Protect, info.AllocationBase, info.RegionSize);
    return info.State == state && (state != MEM_COMMIT || info.Protect == protect);
}
/* Writable/executable success claims must be backed by real write and execute. */
static int check_rwx_works(unsigned char *p)
{
    CHECK(query(p, MEM_COMMIT, PAGE_EXECUTE_READWRITE));
    CHECK(try_write(p + 64, 0x5a));
    write_code(p, 42); CHECK(try_exec(p, 42));
    write_code(p, 43); CHECK(try_exec(p, 43));
    return 0;
}
typedef LONG (WINAPI *nt_allocate_fn)(HANDLE, void **, ULONG_PTR, SIZE_T *, ULONG, ULONG);
static int exec_commit(void)
{
    nt_allocate_fn nt_allocate = (nt_allocate_fn)(void *)GetProcAddress(
        GetModuleHandleW(L"ntdll.dll"), "NtAllocateVirtualMemory"); CHECK(nt_allocate);
    unsigned char *base = VirtualAlloc(NULL, 0x10000, MEM_RESERVE, PAGE_NOACCESS); CHECK(base);
    for (int attempt = 0; attempt < 2; attempt++) {
        unsigned char *page = base + 4096 * (1 + attempt);
        void *addr = page; SIZE_T size = 4096; LONG status = 0; DWORD error = 0;
        if (!attempt) status = nt_allocate(GetCurrentProcess(), &addr, 0, &size, MEM_COMMIT, PAGE_EXECUTE_READWRITE);
        else if (!VirtualAlloc(page, 4096, MEM_COMMIT, PAGE_EXECUTE_READWRITE)) { error = GetLastError(); status = -1; }
        printf("commit %s %p status=0x%lx error=%lu\n", attempt ? "VirtualAlloc" : "NtAllocateVirtualMemory",
               page, (unsigned long)status, error);
        if (!status) { if (check_rwx_works(page)) return 1; continue; }
        CHECK(query(page, MEM_RESERVE, 0));
        CHECK(VirtualAlloc(page, 4096, MEM_COMMIT, PAGE_READWRITE) == page);
        CHECK(query(page, MEM_COMMIT, PAGE_READWRITE)); CHECK(try_write(page, 0x11));
    }
    CHECK(VirtualFree(base, 0, MEM_RELEASE)); return 0;
}
static int exec_protect(void)
{
    unsigned char *p = VirtualAlloc(NULL, 4096, MEM_RESERVE|MEM_COMMIT, PAGE_READWRITE); CHECK(p);
    DWORD old = 0;
    memset(p, 0xa5, 4096); write_code(p, 42);
    if (VirtualProtect(p, 4096, PAGE_EXECUTE_READWRITE, &old)) {
        CHECK(old == PAGE_READWRITE); if (check_rwx_works(p)) return 1;
        CHECK(VirtualProtect(p, 4096, PAGE_READWRITE, &old));
    } else {
        printf("RW->RWX error=%lu\n", GetLastError());
        CHECK(query(p, MEM_COMMIT, PAGE_READWRITE));
        CHECK(p[100] == 0xa5); CHECK(try_write(p + 100, 0x5a));
    }
    write_code(p, 42);
    CHECK(VirtualProtect(p, 4096, PAGE_EXECUTE_READ, &old)); CHECK(old == PAGE_READWRITE);
    CHECK(try_exec(p, 42));
    if (VirtualProtect(p, 4096, PAGE_EXECUTE_READWRITE, &old)) {
        CHECK(old == PAGE_EXECUTE_READ); if (check_rwx_works(p)) return 1;
    } else {
        printf("RX->RWX error=%lu\n", GetLastError());
        CHECK(query(p, MEM_COMMIT, PAGE_EXECUTE_READ)); CHECK(try_exec(p, 42));
    }
    CHECK(VirtualFree(p, 0, MEM_RELEASE)); return 0;
}
static int exec_alloc_state(void)
{
    unsigned char *want = (unsigned char *)(uintptr_t)0x61000000;
    CHECK(query(want, MEM_FREE, 0));  /* fixture address must be free */
    unsigned char *p = VirtualAlloc(want, 4096, MEM_RESERVE|MEM_COMMIT, PAGE_EXECUTE_READWRITE);
    if (p) {
        CHECK(p == want); if (check_rwx_works(p)) return 1;
        CHECK(VirtualFree(p, 0, MEM_RELEASE));
    } else printf("RWX alloc error=%lu\n", GetLastError());
    CHECK(query(want, MEM_FREE, 0));
    p = VirtualAlloc(want, 4096, MEM_RESERVE|MEM_COMMIT, PAGE_READWRITE); CHECK(p == want);
    CHECK(try_write(p, 1)); CHECK(VirtualFree(p, 0, MEM_RELEASE)); return 0;
}
/* Write-watch makes adjacent pages need different host protections, so one
 * host run can succeed before a later run fails, without failure injection. */
static int exec_rollback(void)
{
    unsigned char *p = VirtualAlloc(NULL, 8192, MEM_RESERVE|MEM_COMMIT|MEM_WRITE_WATCH, PAGE_READWRITE);
    CHECK(p); CHECK(!ResetWriteWatch(p, 8192));
    p[4096 + 8] = 0x22;  /* clears only page 2's watch */
    DWORD old = 0;
    if (VirtualProtect(p, 8192, PAGE_EXECUTE_READWRITE, &old)) {
        if (check_rwx_works(p) || check_rwx_works(p + 4096)) return 1;
    } else {
        printf("watched RW->RWX error=%lu\n", GetLastError());
        CHECK(query(p, MEM_COMMIT, PAGE_READWRITE)); CHECK(query(p + 4096, MEM_COMMIT, PAGE_READWRITE));
        CHECK(p[4096 + 8] == 0x22);
        CHECK(try_write(p + 8, 0x33)); CHECK(try_write(p + 4096 + 16, 0x44));
    }
    CHECK(VirtualFree(p, 0, MEM_RELEASE)); return 0;
}
/* Non-injected control: a range covering a committed and a reserved page must
 * be refused without changing either page (Windows VirtualProtect contract). */
static int exec_protect_span(void)
{
    unsigned char *p = VirtualAlloc(NULL, 8192, MEM_RESERVE, PAGE_NOACCESS); CHECK(p);
    CHECK(VirtualAlloc(p, 4096, MEM_COMMIT, PAGE_READWRITE) == p);
    DWORD old = 0;
    CHECK(!VirtualProtect(p, 8192, PAGE_READONLY, &old));
    printf("span protect error=%lu\n", GetLastError());
    CHECK(query(p, MEM_COMMIT, PAGE_READWRITE)); CHECK(query(p + 4096, MEM_RESERVE, 0));
    CHECK(try_write(p, 0x55)); CHECK(VirtualFree(p, 0, MEM_RELEASE)); return 0;
}
static void count_reservations(SIZE_T *regions, SIZE_T *bytes)
{
    MEMORY_BASIC_INFORMATION info;
    unsigned char *addr = NULL;
    *regions = *bytes = 0;
    while (VirtualQuery(addr, &info, sizeof(info)) == sizeof(info)) {
        if (info.State != MEM_FREE && info.Type == MEM_PRIVATE) {
            if (info.AllocationBase == info.BaseAddress) ++*regions;
            *bytes += info.RegionSize;
        }
        if ((unsigned char *)info.BaseAddress + info.RegionSize <= addr) break;
        addr = (unsigned char *)info.BaseAddress + info.RegionSize;
    }
}
static int exec_heap_leak(void)
{
    SIZE_T regions0, bytes0, regions1, bytes1;
    unsigned created = 0;
    HANDLE warm = HeapCreate(HEAP_CREATE_ENABLE_EXECUTE, 0, 0);
    if (warm) CHECK(HeapDestroy(warm));
    count_reservations(&regions0, &bytes0);
    for (int i = 0; i < 32; i++) {
        HANDLE heap = HeapCreate(HEAP_CREATE_ENABLE_EXECUTE, 0, 0);
        if (heap) { created++; CHECK(HeapDestroy(heap)); }
    }
    count_reservations(&regions1, &bytes1);
    printf("exec heaps created=%u/32 private allocations %zu->%zu bytes 0x%zx->0x%zx\n",
           created, regions0, regions1, bytes0, bytes1);
    CHECK(regions1 == regions0 && bytes1 == bytes0);
    return 0;
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
    else if (!strcmp(argv[1], "exec-heap") || !strcmp(argv[1], "exec-rwx") ||
             !strcmp(argv[1], "exec-transition")) result=executable_memory(argv[1]);
    else if (!strcmp(argv[1], "exec-commit")) result=exec_commit();
    else if (!strcmp(argv[1], "exec-protect")) result=exec_protect();
    else if (!strcmp(argv[1], "exec-alloc-state")) result=exec_alloc_state();
    else if (!strcmp(argv[1], "exec-rollback")) result=exec_rollback();
    else if (!strcmp(argv[1], "exec-protect-span")) result=exec_protect_span();
    else if (!strcmp(argv[1], "exec-heap-leak")) result=exec_heap_leak();
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
