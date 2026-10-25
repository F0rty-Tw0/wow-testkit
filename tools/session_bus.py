"""The event bus of a session: fan-out of (event, data) from the LuaHost to every /stream client (session_http.py)."""

import queue
import threading

QUEUE_SIZE = 256


class Subscriber:
    """One /stream client: a bounded queue; a client that falls 256 events behind is dropped."""

    def __init__(self):
        self.q = queue.Queue(maxsize=QUEUE_SIZE)
        self.dead = False


class Bus:
    """Fan-out of (event, data) to every /stream client."""

    def __init__(self):
        self.lock = threading.Lock()
        self.subscribers = []

    def subscribe(self):
        sub = Subscriber()
        with self.lock:
            self.subscribers.append(sub)
        return sub

    def unsubscribe(self, sub):
        with self.lock:
            if sub in self.subscribers:
                self.subscribers.remove(sub)

    def publish(self, event, data):
        with self.lock:
            for sub in list(self.subscribers):
                try:
                    sub.q.put_nowait((event, data))
                except queue.Full:
                    sub.dead = True
                    self.subscribers.remove(sub)

    def close(self):
        """Wakes every /stream handler so it ends."""
        with self.lock:
            for sub in self.subscribers:
                sub.dead = True
                try:
                    sub.q.put_nowait(None)
                except queue.Full:
                    pass
            self.subscribers.clear()
